#!/bin/bash

source ./envfile

# Create namespaces where the secret will be
#oc new-project hive
#oc new-project artifactory
oc new-project ${TPA_NAMESPACE}
oc new-project openshift-storage
oc create namespace openshift-storage

# TPA - Grant Security Context Constraints (SCCs): Grant the non-root MinIO and PostgreSQL components the ability to run in the application namespaces.
#oc adm policy add-scc-to-user anyuid -z default -n minio-operator
#oc adm policy add-scc-to-user anyuid -z minio-operator -n minio-operator
#oc adm policy add-scc-to-user anyuid -z default -n ${TPA_NAMESPACE}

# Secret 1: TPA DB Connection Details (postgresql-credentials)
oc create secret generic postgresql-credentials -n ${TPA_NAMESPACE} \
  --from-literal=db.host="tpa-postgres-primary.${TPA_NAMESPCE}.svc.cluster.local" \
  --from-literal=db.port='5432' \
  --from-literal=db.name='tpa-db' \
  --from-literal=db.user='tpa-user' \
  --from-literal=db.password=${TPA_USER_DB_PASS}

# Secret 2: TPA DB Admin Credentials (postgresql-admin-credentials)
oc create secret generic postgresql-admin-credentials -n ${TPA_NAMESPACE} \
  --from-literal=db.host="tpa-postgres-primary.${TPA_NAMESPACE}.svc.cluster.local" \
  --from-literal=db.port='5432' \
  --from-literal=db.name='tpa-db' \
  --from-literal=db.user='postgres' \
  --from-literal=db.password=${PG_ADMIN_PASS}

# Secret 4: OIDC Client Secret (oidc-cli)
oc create secret generic oidc-cli -n ${TPA_NAMESPACE} \
  --from-literal=client-secret=${OIDC_CLIENT_SECRET}

# Secret 5: Keycloak Admin Login (keycloak-admin-secret)
oc create secret generic keycloak-admin-secret -n ${TPA_NAMESPACE} \
  --from-literal=username='kcadmin' --from-literal=password=${KC_ADMIN_PASSWORD}

# Create secrets
#echo "Creating Pull Secret"
#oc create secret generic global-pull-secret --type=kubernetes.io/dockerconfigjson --from-literal=.dockerconfigjson="$PULL_SECRET" -n hive

#echo "Creating AWS creds secret"
#oc create secret generic hive-aws-creds -n hive --from-literal=aws_access_key_id="$AWS_ACCESS_KEY_ID" --from-literal=aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"

