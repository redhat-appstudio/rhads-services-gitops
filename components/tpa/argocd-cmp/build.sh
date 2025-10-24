#!/bin/bash
set -euo pipefail

# This script runs during ArgoCD manifest generation
# It queries the cluster for ingress domain and generates the ConfigMap,
# then runs kustomize build

# Get cluster ingress domain
INGRESS_DOMAIN=$(oc -n openshift-ingress-operator get ingresscontrollers.operator.openshift.io default -o jsonpath='{.status.domain}' 2>/dev/null || echo "apps.example.com")

# Set namespace variables
TPA_NAMESPACE="tssc-tpa"
REALM="chicken"

# Derive values
APP_DOMAIN_URL="-${TPA_NAMESPACE}.${INGRESS_DOMAIN}"
KEYCLOAK_HOST="sso.${INGRESS_DOMAIN}"
OIDC_ISSUER_URL="https://sso.${INGRESS_DOMAIN}/realms/${REALM}"

# Create temporary ConfigMap file
cat > /tmp/tpa-values-configmap.yaml <<EOF
apiVersion: v1
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

# Update kustomization.yaml to include the generated ConfigMap
# Remove the generators section and add the ConfigMap as a resource
cp kustomization.yaml kustomization.yaml.bak
sed '/^generators:/,/^[a-z]/d' kustomization.yaml.bak > kustomization.yaml.tmp
sed '/^resources:/a\  - /tmp/tpa-values-configmap.yaml' kustomization.yaml.tmp > kustomization.yaml

# Run kustomize build
kustomize build .

# Cleanup
rm -f kustomization.yaml.tmp kustomization.yaml.bak
