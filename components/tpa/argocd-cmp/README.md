# TPA ArgoCD Config Management Plugin (CMP)

This directory contains the ArgoCD Config Management Plugin configuration for the TPA component.

## Purpose

The CMP solves the problem of generating cluster-specific values at **build time** (during `kustomize build`) rather than at runtime. This ensures that kustomize replacements work correctly with real cluster values.

## The Problem It Solves

Without the CMP, there's a race condition:
1. ArgoCD runs `kustomize build` with placeholder values (e.g., `apps.example.com`)
2. Kustomize replacements inject these placeholders into the Application manifest
3. A runtime hook generates the real ConfigMap with cluster-specific values
4. **But it's too late** - the Application already has placeholder values baked in

## How It Works

The CMP runs during ArgoCD's manifest generation phase and:
1. Queries the OpenShift IngressController API for the actual cluster domain
2. Generates a ConfigMap with real cluster-specific values
3. Modifies the kustomization.yaml to include this generated ConfigMap
4. Runs `kustomize build` with the real values

This ensures kustomize replacements use real cluster values from the start.

## Components

### cmp-plugin.yaml
ConfigMap containing the plugin configuration with the generation script that:
- Queries the cluster for ingress domain
- Generates the `tpa-values-source` ConfigMap
- Modifies kustomization.yaml dynamically
- Runs kustomize build

### cmp-rbac.yaml
RBAC resources for the CMP:
- ServiceAccount: `argocd-repo-server-cmp`
- ClusterRole: permissions to read IngressControllers
- ClusterRoleBinding: binds the role to the service account

### Bootstrap Integration

The `bootstrap.sh` script:
1. Applies the CMP configuration (`cmp-plugin.yaml` and `cmp-rbac.yaml`)
2. Patches the ArgoCD CR to add:
   - Init container to download `oc` CLI
   - CMP sidecar container with both `kustomize` and `oc`
   - Custom volumes for tools sharing
   - ServiceAccount configuration

## Sidecar Configuration

The CMP sidecar:
- **Base image**: `quay.io/argoproj/argocd:latest` (has kustomize)
- **Init container**: Downloads and installs `oc` CLI from OpenShift mirror
- **Tools available**: Both `kustomize` and `oc`
- **ServiceAccount**: `argocd-repo-server-cmp` with IngressController read permissions

## Usage

The TPA Application in `app-of-apps/tpa.yaml` is configured to use this plugin:
```yaml
spec:
  source:
    plugin:
      name: tpa-kustomize
```

When ArgoCD syncs, it:
1. Detects the plugin reference
2. Routes the build to the CMP sidecar
3. CMP queries cluster and generates ConfigMap
4. Kustomize replacements use real values
5. Application gets correct helm parameters

## Files

- **cmp-plugin.yaml**: Plugin configuration and generation script
- **cmp-rbac.yaml**: RBAC for cluster access
- **Dockerfile**: Reference only - not used (we use base ArgoCD image + init container)
- **build.sh**: Reference only - logic is in cmp-plugin.yaml
- **plugin.yaml**: Reference only - configuration is in cmp-plugin.yaml
- **argocd-cmp-sidecar.yaml**: Reference only - configuration is in bootstrap.sh

## Alternative Approaches Considered

1. **Exec Plugin**: Doesn't work - runs in repo-server without cluster access
2. **Hook-based**: Has race condition - generates ConfigMap after kustomize build
3. **CMP with curl**: Current approach - can access cluster API during build

## Current Status

**Status**: In development
- ✅ CMP sidecar configured with oc and kustomize
- ✅ RBAC configured for IngressController access
- ⚠️ ServiceAccount token mounting issue to resolve
- 🔧 Plugin needs updating to use curl for API access (workaround for token mounting)
