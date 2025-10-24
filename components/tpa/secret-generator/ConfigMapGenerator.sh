#!/bin/bash
set -euo pipefail

# Read ResourceList from stdin (KRM function interface requirement)
cat > /dev/null

# Get cluster ingress domain
INGRESS_DOMAIN=$(oc -n openshift-ingress-operator get ingresscontrollers.operator.openshift.io default -o jsonpath='{.status.domain}' 2>/dev/null || echo "apps.example.com")

# Set namespace variables
TPA_NAMESPACE="tssc-tpa"
REALM="chicken"

# Derive values
APP_DOMAIN_URL="-${TPA_NAMESPACE}.${INGRESS_DOMAIN}"
KEYCLOAK_HOST="sso.${INGRESS_DOMAIN}"
OIDC_ISSUER_URL="https://sso.${INGRESS_DOMAIN}/realms/${REALM}"

# Function to get existing secret or generate new
get_or_generate_password() {
  local namespace=$1
  local name=$2
  local key=$3
  local length=${4:-16}

  existing=$(oc get secret "$name" -n "$namespace" -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d || echo "")
  if [ -n "$existing" ]; then
    echo "  Reusing existing password for $name/$key" >&2
    echo "$existing"
  else
    echo "  Generating new password for $name/$key" >&2
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c "$length"
  fi
}

get_or_generate_uuid_password() {
  local namespace=$1
  local name=$2
  local key=$3

  existing=$(oc get secret "$name" -n "$namespace" -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d || echo "")
  if [ -n "$existing" ]; then
    echo "  Reusing existing password for $name/$key" >&2
    echo "$existing"
  else
    echo "  Generating new UUID-style password for $name/$key" >&2
    random=$(openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c 32)
    echo "${random:0:8}-${random:8:4}-${random:12:4}-${random:16:4}-${random:20:12}"
  fi
}

# Generate or reuse passwords
echo "Processing passwords..."
SEED_STRING=$(get_or_generate_password "$TPA_NAMESPACE" "tpa-realm-chicken-admin" "password" 16)
PASS_CLI=$(get_or_generate_uuid_password "$TPA_NAMESPACE" "tpa-realm-chicken-clients" "cli")
PASS_MANAGER=$(get_or_generate_uuid_password "$TPA_NAMESPACE" "tpa-realm-chicken-clients" "testingManager")
PASS_USER=$(get_or_generate_uuid_password "$TPA_NAMESPACE" "tpa-realm-chicken-clients" "testingUser")
echo ""

# Output KRM ResourceList with ConfigMap
cat <<EOF
apiVersion: config.kubernetes.io/v1
kind: ResourceList
items:
- apiVersion: v1
  kind: ConfigMap
  metadata:
    name: tpa-values-source
    namespace: ${TPA_NAMESPACE}
    annotations:
      argocd.argoproj.io/sync-options: Prune=false
  data:
    APP_DOMAIN_URL: "${APP_DOMAIN_URL}"
    OIDC_ISSUER_URL: "${OIDC_ISSUER_URL}"
    KEYCLOAK_HOSTNAME: "${KEYCLOAK_HOST}"
    REDIRECT_URI1: "https://server${APP_DOMAIN_URL}"
    REDIRECT_URI2: "https://server${APP_DOMAIN_URL}/*"
    REDIRECT_URI3: "https://sbom${APP_DOMAIN_URL}"
    REDIRECT_URI4: "https://sbom${APP_DOMAIN_URL}/*"
    CLI: "${PASS_CLI}"
    MANAGER: "${PASS_MANAGER}"
    USER: "${PASS_USER}"
    SEED: "${SEED_STRING}" 
EOF
