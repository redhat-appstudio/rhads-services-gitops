# ArgoCD Config Management Plugin for TPA
# This sidecar adds oc CLI and custom kustomize build logic

FROM quay.io/argoproj/argocd:latest

# Switch to root to install packages
USER root

# Install oc CLI from OpenShift mirror
RUN curl -sLo /tmp/oc.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && \
    tar -xzf /tmp/oc.tar.gz -C /usr/local/bin oc && \
    chmod +x /usr/local/bin/oc && \
    rm /tmp/oc.tar.gz

# Copy the plugin configuration
COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml

# Copy the build script
COPY build.sh /usr/local/bin/tpa-build.sh
RUN chmod +x /usr/local/bin/tpa-build.sh

# Switch back to argocd user
USER argocd

WORKDIR /home/argocd
