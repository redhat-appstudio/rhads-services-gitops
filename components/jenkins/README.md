# Jenkins on OpenShift 4.19

Jenkins installation for TSSC (Trusted Software Supply Chain) with custom build agent supporting rootless buildah for container builds.

## Overview

This deployment provides:
- **Jenkins Controller**: Helm chart-based Jenkins installation
- **Custom Build Agent**: UBI9-based agent with buildah, syft, cosign, and Python 3.11
- **Authentication**: OpenShift OAuth (no username/password)
- **Security**: OpenShift restricted-v2 SCC with custom SCC for buildah capabilities
- **GitOps**: ArgoCD-managed deployment

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Jenkins Controller (StatefulSet)                    │
│ - JCasC Configuration                               │
│ - Kubernetes Cloud Plugin                           │
│ - Dynamic Agent Provisioning                        │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│ Jenkins Build Agent (Pod Template)                  │
│ - Image: quay.io/rhtap/tssc-jenkins-agent:latest       │
│ - Python 3.11 (for hashlib.file_digest)            │
│ - Buildah (rootless, chroot isolation, vfs)        │
│ - Tools: syft, cosign, ec, jq, yq, git-lfs         │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│ Security Context Constraints                        │
│ - restricted-v2: Jenkins controller                │
│ - jenkins-agent-base: Buildah with SETUID/SETGID   │
└─────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `kustomization.yaml` | Kustomize configuration for ArgoCD |
| `namespace.yaml` | Jenkins namespace definition |
| `values.yaml` | Helm chart values with pod templates |
| `scc.yaml` | Custom SCC for buildah capabilities |
| `scc-rolebinding.yaml` | Binds jenkins SA to jenkins-agent-base SCC |
| `rbac.yaml` | Additional RBAC for Jenkins operations |
| `agent/Dockerfile` | Custom agent image definition (manual build) |
| `agent/README.md` | Build instructions for custom agent image |

## Prerequisites

- OpenShift 4.19+
- ArgoCD installed in `openshift-gitops` namespace
- Access to quay.io or container registry
- Admin permissions for SCC creation

## Installation

### 1. ArgoCD Application

The ArgoCD application is defined in [app-of-apps/jenkins.yaml](../../app-of-apps/jenkins.yaml).

### 2. Build Custom Agent Image

See [agent/README.md](agent/README.md) for build instructions.

### 3. Verify Deployment

```bash
# Check ArgoCD sync status
kubectl get application jenkins -n gitops-resources

# Check Jenkins pods
kubectl get pods -n jenkins

# Access Jenkins UI
kubectl get route jenkins -n jenkins -o jsonpath='{.spec.host}'
```

## Configuration Details

### Authentication and Security

**OpenShift OAuth Integration:**
- Jenkins uses OpenShift OAuth for authentication (via `openshift-login` plugin)
- Users authenticate with OpenShift cluster credentials
- No separate Jenkins admin password required
- ServiceAccount-based OAuth with Route redirect URL resolution

**Security Settings:**
- `disableRememberMe: true` - Ensures sessions expire with OAuth tokens
- `excludeClientIPFromCrumb: true` - CSRF protection compatible with proxies/load balancers
- `GlobalMatrixAuthorizationStrategy` - Required by openshift-login plugin

**Environment Variables:**
```yaml
OPENSHIFT_ENABLE_OAUTH: "true"
OPENSHIFT_PERMISSIONS_POLL_INTERVAL: "300000"  # Poll every 5 minutes
```

**JCasC (Jenkins Configuration as Code):**

The OAuth integration is configured via JCasC in `values.yaml`:

```yaml
JCasC:
  defaultConfig: false
  configScripts:
    jenkins-config: |
      jenkins:
        authorizationStrategy:
          globalMatrix:
            entries:
              - group:
                  name: "authenticated"
                  permissions:
                    - "Overall/Read"
        disableRememberMe: true
        crumbIssuer:
          standard:
            excludeClientIPFromCrumb: true
      security:
        apiToken:
          creationOfLegacyTokenEnabled: false
          tokenGenerationOnCreationEnabled: false
```

Key settings:
- `authorizationStrategy: globalMatrix` - Required by openshift-login plugin
- `authenticated` group with `Overall/Read` permission - Allows OAuth users to access Jenkins
- `disableRememberMe: true` - Ensures sessions expire with OAuth tokens
- `excludeClientIPFromCrumb: true` - CSRF protection compatible with proxies/load balancers
- API token settings - Controls token creation behavior

**RBAC Configuration:**

ServiceAccount with OAuth redirect annotation in `values.yaml`:

```yaml
rbac:
  create: true
  useOpenShiftNonRootSCC: true
  serviceAccount:
    create: true
    name: "jenkins"
    annotations:
      serviceaccounts.openshift.io/oauth-redirectreference.jenkins:
        '{"kind":"OAuthRedirectReference","apiVersion":"v1","reference":{"kind":"Route","name":"jenkins"}}'
```

The OAuth redirect annotation is **critical** - it enables dynamic Route-based redirect URL resolution without requiring a separate OAuthClient resource.

**Required Plugins:**

Essential plugins for OAuth integration (from `values.yaml`):
- `openshift-login` - OpenShift OAuth authentication provider
- `matrix-auth` - Provides GlobalMatrixAuthorizationStrategy
- `configuration-as-code` - JCasC functionality

### Buildah Rootless Configuration

The agent uses buildah in rootless mode with the following settings:

**Environment Variables:**
```yaml
_BUILDAH_STARTED_IN_USERNS: ""        # Prevents nested user namespaces
BUILDAH_ISOLATION: chroot             # Use chroot isolation (not OCI)
STORAGE_DRIVER: vfs                   # Required for restricted SCC
```

**Storage Configuration** (`~/.config/containers/storage.conf`):
```ini
[storage]
driver = "vfs"
```

**Why VFS and not Overlay?**
- Overlay requires FUSE support (not available in restricted-v2 SCC)
- VFS works without special kernel features
- Slower but compatible with OpenShift security constraints

### Security Context Constraints

**jenkins-agent-base SCC:**
- Allows `SETUID` and `SETGID` capabilities
- Required for buildah's newuidmap/newgidmap binaries
- Assigned to `system:serviceaccount:jenkins:jenkins`

**Configuration:**
```yaml
allowedCapabilities:
- SETUID
- SETGID
users:
- system:serviceaccount:jenkins:jenkins
```

### Pod Template

The `tssc` pod template includes:

**Init Container (agent-injector):**
- Copies Jenkins agent JAR from `jenkins/inbound-agent:3341.v0766d82b_dec0-1`
- Mounts to `/agent-volume` for main container

**Main Container (jnlp):**
- Image: `quay.io/rhtap/tssc-jenkins-agent:latest`
- Resources: 256Mi-1Gi memory, 100m-500m CPU
- Volumes: workspace, agent JAR, buildah storage (emptyDir)

## Troubleshooting

### Issue: buildah fails with "fuse-overlayfs: cannot mount"

**Cause:** Trying to use overlay storage driver without FUSE support.

**Solution:** Ensure `STORAGE_DRIVER=vfs` is set and storage.conf uses `driver = "vfs"`.

### Issue: "AttributeError: module 'hashlib' has no attribute 'file_digest'"

**Cause:** Python < 3.11 doesn't have `hashlib.file_digest()`.

**Solution:** Rebuild agent image with Python 3.11:
```dockerfile
RUN microdnf install -y python3.11 python3.11-pip
RUN alternatives --set python3 /usr/bin/python3.11
```

### Issue: Pod uses restricted-v2 SCC instead of jenkins-agent-base

**Cause:** SCC users list is empty or missing jenkins service account.

**Solution:** Verify SCC has correct user:
```bash
kubectl get scc jenkins-agent-base -o yaml | grep -A 5 users:
```

Should show: `system:serviceaccount:jenkins:jenkins`

### Issue: "Error during unshare(CLONE_NEWUSER): Function not implemented"

**Cause:** Buildah trying to create user namespaces in restricted environment.

**Solution:**
- Set `BUILDAH_ISOLATION=chroot`
- Set `_BUILDAH_STARTED_IN_USERNS=""`
- Remove UID/GID remapping from storage.conf

## Maintenance

### Update Agent Image

1. Modify `agent/Dockerfile`
2. Build and push new image (see [agent/README.md](agent/README.md) for build instructions)
3. Restart agent pods:
   ```bash
   kubectl delete pods -n jenkins -l jenkins/label=tssc-jenkins-agent
   ```

### Update Helm Values

1. Modify `values.yaml`
2. Commit and push to repository
3. ArgoCD auto-syncs changes
4. Verify: `kubectl get configmap jenkins-jenkins-jcasc-config -n jenkins -o yaml`

## Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| **VFS storage driver** | Overlay requires FUSE (unavailable in restricted SCC) |
| **Chroot isolation** | Avoids user namespace requirements |
| **Python 3.11** | Required for `hashlib.file_digest()` in merge_sboms.py |
| **UID 1001 / GID 0** | OpenShift arbitrary UID standard with root group |
| **No UID/GID remapping** | Prevents /etc/subuid errors with chroot isolation |
| **SETUID/SETGID in SCC** | Required for newuidmap/newgidmap capabilities |
| **Agent injection pattern** | Allows custom base image with Jenkins agent JAR |

## References

- [Buildah OpenShift Rootless Tutorial](https://github.com/containers/buildah/blob/main/docs/tutorials/05-openshift-rootless-build.md)
- [Jenkins Helm Chart](https://github.com/jenkinsci/helm-charts/tree/main/charts/jenkins)
- [OpenShift SCC Documentation](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
