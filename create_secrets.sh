#!/bin/bash

source ./envfile

# Create namespaces where the secret will be
#oc new-project hive
#oc new-project artifactory
oc new-project ${TPA_NAMESPACE}
oc new-project rhbk-operator
oc new-project tssc-keycloak

# Secret 1: TPA DB Connection Details 
cat <<EOF | oc apply -f - -n $TPA_NAMESPACE
apiVersion: v1
kind: Secret
type: Opaque
metadata:   
  name: tpa-pgsql-user
  namespace: $TPA_NAMESPACE 
stringData:
  dbname: tpa
  host: tpa-pgsql.tssc-tpa.svc
  user: tpa   
  port: "5432"
  password: "$TPA_USER_DB_PASS"
EOF

# Secret 2: Keycloak DB Connection Details
cat <<EOF | oc apply -f - -n $KEYCLOAK_NAMESPACE
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: keycloak-pgsql-user
  namespace: $KEYCLOAK_NAMESPACE
stringData:
  dbname: keycloak
  host: keycloak-pgsql.tssc-keycloak.svc
  user: keycloak
  port: "5432"
  password: "$KEYCLOAK_USER_DB_PASS"
EOF

# Secret 3: Realm admin secret
cat <<EOF | oc apply -f - -n $TPA_NAMESPACE
apiVersion: v1
kind: Secret
metadata:
  annotations:
    helm.sh/resource-policy: keep
  labels:
    app: keycloak
  namespace: $TPA_NAMESPACE
  name: tpa-realm-chicken-admin
type: Opaque
data:
  username: $REALM_USER_B64
  password: $REALM_ADMIN_PASS_B64
EOF

# Add Secret to keycloak namespace for placeholders
cat <<EOF | oc apply -f - -n $KEYCLOAK_NAMESPACE
apiVersion: v1
kind: Secret
metadata:
  annotations:
    helm.sh/resource-policy: keep
  labels:
    app: keycloak
  namespace: $KEYCLOAK_NAMESPACE
  name: tpa-realm-chicken-admin
type: Opaque
stringData:
  username: admin
  password: $SEED_STRING
EOF

# Secret 4: OIDC Client Secrets (oidc cli, manager, user)
cat <<EOF | oc apply -f - -n $TPA_NAMESPACE
apiVersion: v1
kind: Secret
metadata:
  annotations:
    helm.sh/resource-policy: keep
  labels:
    app: keycloak
  namespace: $TPA_NAMESPACE
  name: tpa-realm-chicken-clients
type: Opaque
data:
  cli: $PASS_CLI_B64
  testingManager: $PASS_MANAGER_B64
  testingUser: $PASS_USER_B64
EOF

# Add Secret to keycloak namespace for placeholders
cat <<EOF | oc apply -f - -n $KEYCLOAK_NAMESPACE
apiVersion: v1
kind: Secret
metadata:
  annotations:
    helm.sh/resource-policy: keep
  labels:
    app: keycloak
  namespace: $KEYCLOAK_NAMESPACE
  name: tpa-realm-chicken-clients
type: Opaque
stringData:
  cli: $PASS_CLI
  testingManager: $PASS_MANAGER
  testingUser: $PASS_USER
EOF

# Secret 5: trustification integration
cat <<EOF | oc apply -f - -n $TPA_NAMESPACE
apiVersion: v1
kind: Secret
metadata:
  labels:
    app: keycloak
  namespace: $TPA_NAMESPACE
  name: tssc-trustification-integration
  annotations:
    helm.sh/resource-policy: keep
type: Opaque
stringData:
  bombastic_api_url: https://server$APP_DOMAIN_URL
  oidc_issuer_url: https://sso.$INGRESS_URL/realms/$REALM
  oidc_client_id: cli
  oidc_client_secret: $PASS_CLI
  supported_cyclonedx_version: "${CYCLONEDX_VER}"
EOF

# TPA - Update literals of components/tpa/kustomization.yaml
yq -i '(.configMapGenerator[].literals[] | select(test("^APP_DOMAIN_URL="))) |= "APP_DOMAIN_URL=" + env(APP_DOMAIN_URL)' ./components/tpa/kustomization.yaml
yq -i '(.configMapGenerator[].literals[] | select(test("^OIDC_ISSUER_URL="))) |= "OIDC_ISSUER_URL=" + env(OIDC_ISSUER_URL)' ./components/tpa/kustomization.yaml
yq -i '(.configMapGenerator[].literals[] | select(test("^KEYCLOAK_HOSTNAME="))) |= "KEYCLOAK_HOSTNAME=" + env(KEYCLOAK_HOST)' ./components/tpa/kustomization.yaml
yq -i '(.configMapGenerator[].literals[] | select(test("^REDIRECT_URI1="))) |= "REDIRECT_URI1=https://server" + env(APP_DOMAIN_URL)' ./components/tpa/kustomization.yaml
yq -i '(.configMapGenerator[].literals[] | select(test("^REDIRECT_URI2="))) |= "REDIRECT_URI2=https://server" + env(APP_DOMAIN_URL) + "/*"' ./components/tpa/kustomization.yaml
yq -i '(.configMapGenerator[].literals[] | select(test("^REDIRECT_URI3="))) |= "REDIRECT_URI3=https://sbom" + env(APP_DOMAIN_URL)' ./components/tpa/kustomization.yaml
yq -i '(.configMapGenerator[].literals[] | select(test("^REDIRECT_URI4="))) |= "REDIRECT_URI4=https://sbom" + env(APP_DOMAIN_URL) + "/*"' ./components/tpa/kustomization.yaml
#yq -i '(.configMapGenerator[].literals[] | select(test("^SEED_STRING="))) |= "SEED_STRING=" + env(SEED_STRING)' ./components/tpa/kustomization.yaml

echo "NOTE: Literals updated in components/tpa/kustomization.yaml. Check in and merge changes before running bootstrap.sh"

# Create secrets
#echo "Creating Pull Secret"
#oc create secret generic global-pull-secret --type=kubernetes.io/dockerconfigjson --from-literal=.dockerconfigjson="$PULL_SECRET" -n hive

#echo "Creating AWS creds secret"
#oc create secret generic hive-aws-creds -n hive --from-literal=aws_access_key_id="$AWS_ACCESS_KEY_ID" --from-literal=aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"

