#!/bin/bash

create_subscription() {
    echo "Installing the OpenShift GitOps operator subscription:"
    kubectl apply -k "./components/openshift-gitops"
    echo -n "Waiting for default project (and namespace) to exist: "
    while ! kubectl get appproject/default -n openshift-gitops &>/dev/null; do
        echo -n .
        sleep 1
    done
    echo "OK"
}

wait_for_route() {
    echo -n "Waiting for OpenShift GitOps Route: "
    while ! kubectl get route/openshift-gitops-server -n openshift-gitops &>/dev/null; do
        echo -n .
        sleep 1
    done
    echo "OK"
}

grant_admin_role_to_all_authenticated_users() {
    echo Allow any authenticated users to be admin on the Argo CD instance
    # - Once we have a proper access policy in place, this should be updated to be consistent with that policy.
    kubectl patch argocd/openshift-gitops -n openshift-gitops -p '{"spec":{"rbac":{"policy":"g, system:authenticated, role:admin"}}}' --type=merge
}

apply_tpa_cmp_config() {
    echo "Applying TPA Config Management Plugin configuration"
    kubectl apply -f ./components/tpa/argocd-cmp/cmp-plugin.yaml
    kubectl apply -f ./components/tpa/argocd-cmp/cmp-rbac.yaml
}

patch_argocd_instance() {
    echo "Setting ArgoCD tracking method, sourceNamespaces, and CMP sidecar configuration"
    kubectl patch argocd/openshift-gitops -n openshift-gitops -p '
spec:
  resourceTrackingMethod: annotation
  sourceNamespaces:
    - gitops-resources
  kustomizeBuildOptions: --enable-alpha-plugins --enable-exec
  repo:
    serviceaccount: argocd-repo-server-cmp
    initContainers:
      - name: download-oc
        image: registry.access.redhat.com/ubi8/ubi:latest
        command: ["sh", "-c"]
        args: ["curl -sLo /custom-tools/oc.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz && tar -xzf /custom-tools/oc.tar.gz -C /custom-tools && chmod +x /custom-tools/oc && rm /custom-tools/oc.tar.gz"]
        volumeMounts:
          - mountPath: /custom-tools
            name: custom-tools
    sidecarContainers:
      - name: tpa-cmp-plugin
        command: [/var/run/argocd/argocd-cmp-server]
        image: quay.io/argoproj/argocd:latest
        securityContext:
          runAsNonRoot: true
        volumeMounts:
          - mountPath: /var/run/argocd
            name: var-files
          - mountPath: /home/argocd/cmp-server/plugins
            name: plugins
          - mountPath: /tmp
            name: tmp
          - mountPath: /home/argocd/cmp-server/config/plugin.yaml
            subPath: plugin.yaml
            name: tpa-cmp-plugin
          - mountPath: /usr/local/bin/oc
            name: custom-tools
            subPath: oc
          - mountPath: /var/run/secrets/kubernetes.io/serviceaccount
            name: service-account-token
            readOnly: true
    volumes:
      - name: tpa-cmp-plugin
        configMap:
          name: tpa-cmp-plugin
      - name: custom-tools
        emptyDir: {}
      - name: service-account-token
        projected:
          sources:
            - serviceAccountToken:
                path: token
                expirationSeconds: 3600
            - configMap:
                name: kube-root-ca.crt
                items:
                  - key: ca.crt
                    path: ca.crt
' --type=merge
}


create_namespace_and_AppProject() {
    echo "Creating namespace gitops-resources"
    oc new-project gitops-resources

    echo "Creating new AppProject"
    kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
    name: gitops-resources
    namespace: openshift-gitops
spec:
    clusterResourceWhitelist:
        - group: '*'
          kind: '*'
    destinations:
        - namespace: '*'
          server: '*'
    sourceNamespaces:
        - gitops-resources
    sourceRepos:
        - '*'
EOF
}

create_app_of_apps(){
    echo "Creating app of apps"
    oc create -f ./app-of-apps.yaml
}

create_subscription
wait_for_route
grant_admin_role_to_all_authenticated_users
apply_tpa_cmp_config
patch_argocd_instance
create_namespace_and_AppProject
create_app_of_apps
