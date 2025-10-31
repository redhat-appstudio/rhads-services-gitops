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
EOF
