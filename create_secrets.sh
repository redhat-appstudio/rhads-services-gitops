#!/bin/bash

source ./envfile

# Create namespaces where the secret will be
oc new-project hive
oc new-project artifactory

# Create secrets
echo "Creating Pull Secret"
oc create secret generic global-pull-secret --type=kubernetes.io/dockerconfigjson --from-literal=.dockerconfigjson="$PULL_SECRET" -n hive

echo "Creating AWS creds secret"
oc create secret generic hive-aws-creds -n hive --from-literal=aws_access_key_id="$AWS_ACCESS_KEY_ID" --from-literal=aws_secret_access_key="$AWS_SECRET_ACCESS_KEY"

