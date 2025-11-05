# Jenkins on OpenShift 4.19

Jenkins installation for TSSC (Trusted Software Supply Chain) with custom build agent supporting rootless buildah for container builds.

## Overview

This deployment provides:
- **Jenkins Controller**: Helm chart-based Jenkins installation with JCasC
- **Inline Pod Templates**: Jenkinsfile-defined agent pods with single runner container
- **Build Container**: Uses `rhtap-task-runner` with buildah, syft, cosign tools
- **Authentication**: OpenShift OAuth (no username/password)
- **Security**: Privileged SCC for buildah operations, restricted-v2 for controller
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
│ Jenkinsfile (Inline Pod Template Definition)       │
│ - Pod spec defined in pipeline code                │
│ - Single runner container with privileged mode     │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│ Agent Pod (Dynamic)                                 │
│  ┌─────────────────────────────────────────────┐   │
│  │ Runner Container                            │   │
│  │ - rhtap-task-runner:latest                  │   │
│  │ - Buildah (privileged mode)                 │   │
│  │ - Tools: syft, cosign, ec, jq, yq           │   │
│  │ - RHTAP scripts (/work/* copied to workspace)│  │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│ Security Context Constraints                        │
│ - restricted-v2: Jenkins controller                │
│ - privileged: Runner container (buildah)           │
│ - jenkins-agent-base: Available for custom setups  │
└─────────────────────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `kustomization.yaml` | Kustomize configuration for ArgoCD |
| `namespace.yaml` | Jenkins namespace definition |
| `values.yaml` | Helm chart values (Jenkins configuration) |
| `scc.yaml` | Custom SCC for buildah capabilities (jenkins-agent-base) |
| `scc-rolebinding.yaml` | Binds jenkins SA to jenkins-agent-base SCC |
| `scc-privileged-rolebinding.yaml` | Binds jenkins SA to privileged SCC for inline pod templates |
| `rbac.yaml` | Additional RBAC for Jenkins operations |
| `agent/Dockerfile` | Custom agent image definition (optional) |
| `agent/README.md` | Build instructions for custom agent image (optional) |

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

**RBAC and ServiceAccount Configuration:**

RBAC and ServiceAccount configuration in `values.yaml`:

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

**Important**: The `serviceAccount` section must be at the **top level**, not nested under `rbac`. The Jenkins Helm chart (version 5.8.104) does not support `rbac.serviceAccount.annotations`.

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

**Privileged SCC for Inline Pod Templates:**
- Grants full container privileges for inline Jenkinsfile pod templates
- Required when using `privileged: true` in container security context
- Enabled via `scc-privileged-rolebinding.yaml`

**Configuration:**
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-scc-privileged
  namespace: jenkins
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: jenkins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:openshift:scc:privileged
```

**When to use each SCC:**
- **jenkins-agent-base:** Pre-configured pod templates with agent injection (requires Java in image)
- **privileged:** Inline Jenkinsfile pod templates with advanced container operations (e.g., buildah with privileged mode)

### Inline Jenkinsfile Pod Templates

The recommended approach is to define pod templates directly in Jenkinsfiles using inline Kubernetes YAML. This provides maximum flexibility and works with the `rhtap-task-runner` image.

**Example Jenkinsfile:**

```groovy
pipeline {
  agent {
    kubernetes {
      yaml """
      apiVersion: v1
      kind: Pod
      spec:
        containers:
        - name: 'runner'
          image: 'quay.io/redhat-appstudio/rhtap-task-runner:latest'
          securityContext:
            privileged: true
      """
    }
  }
  environment {
    HOME = "${WORKSPACE}"
    DOCKER_CONFIG = "${WORKSPACE}/.docker"
    ROX_CENTRAL_ENDPOINT = credentials('ROX_CENTRAL_ENDPOINT')
    GITOPS_AUTH_USERNAME = credentials('GITOPS_AUTH_USERNAME')
    IMAGE_REGISTRY_USER = credentials('IMAGE_REGISTRY_USER')
    REKOR_HOST = credentials('REKOR_HOST')
    TUF_MIRROR = credentials('TUF_MIRROR')
    COSIGN_PUBLIC_KEY = credentials('COSIGN_PUBLIC_KEY')
    ROX_API_TOKEN = credentials('ROX_API_TOKEN')
    GITOPS_AUTH_PASSWORD = credentials('GITOPS_AUTH_PASSWORD')
    IMAGE_REGISTRY_PASSWORD = credentials('IMAGE_REGISTRY_PASSWORD')
    COSIGN_SECRET_PASSWORD = credentials('COSIGN_SECRET_PASSWORD')
    COSIGN_SECRET_KEY = credentials('COSIGN_SECRET_KEY')
  }
  stages {
    stage('pre-init') {
      steps {
        container('runner') {
          sh '''
          cp -R /work/* .
          env
          git config --global --add safe.directory $WORKSPACE
          '''
        }
      }
    }
    stage('init') {
      steps {
        container('runner') {
          sh './rhtap/init.sh'
        }
      }
    }
    stage('build') {
      steps {
        container('runner') {
          sh '''
          ./rhtap/buildah-rhtap.sh
          ./rhtap/cosign-sign-attest.sh
          '''
        }
      }
    }
    stage('deploy') {
      steps {
        container('runner') {
          sh './rhtap/update-deployment.sh'
        }
      }
    }
    stage('scan') {
      steps {
        container('runner') {
          sh '''
          ./rhtap/acs-deploy-check.sh
          ./rhtap/acs-image-check.sh
          ./rhtap/acs-image-scan.sh
          '''
        }
      }
    }
    stage('summary') {
      steps {
        container('runner') {
          sh '''
          ./rhtap/show-sbom-rhdh.sh
          ./rhtap/summary.sh
          '''
        }
      }
    }
  }
}
```

**Key Configuration Points:**
- **Single container:** Uses only `rhtap-task-runner` as the runner container
- **Privileged mode:** Required for buildah operations (`privileged: true`)
- **SCC requirement:** Requires `scc-privileged-rolebinding.yaml` to grant privileged SCC access
- **Environment variables:** Jenkins credentials automatically mounted for RHTAP scripts
- **RHTAP stages:** Complete pipeline with init, build, deploy, scan, and summary stages
- **Workspace:** HOME set to `${WORKSPACE}` for proper buildah operation
- **Reference:** Based on [backend-tests-go-teeeknia Jenkinsfile](https://github.com/xjiangorg/backend-tests-go-teeeknia/blob/main/Jenkinsfile)

### Pod Template Approaches

This deployment supports two approaches for Jenkins agent pod provisioning:

| Approach | Pre-configured Template | Inline Jenkinsfile Template |
|----------|------------------------|----------------------------|
| **Definition Location** | `values.yaml` under `agent.podTemplates` | Kubernetes YAML in Jenkinsfile |
| **Image Requirements** | Must contain Java + Jenkins agent JAR | Any image (Java not required in build container) |
| **SCC Used** | jenkins-agent-base (SETUID/SETGID) | privileged (full container access) |
| **Reusability** | Shared across all pipelines | Per-pipeline customization |
| **Security Constraints** | More restrictive (SETUID/SETGID only) | Less restrictive (privileged mode) |
| **Flexibility** | Limited to predefined templates | Full pod spec control per pipeline |
| **Current Status** | No templates configured | ✅ **Recommended approach** |

**Why inline templates are recommended:**

1. **Image compatibility:** Works with the `rhtap-task-runner` image that contains all RHTAP tools
2. **Flexibility:** Each pipeline can define custom pod specifications
3. **Simplicity:** Single container approach with privileged mode for buildah
4. **Privileged operations:** Full support for advanced buildah operations

**When to use pre-configured templates:**

- Custom agent images with Java runtime pre-installed
- Shared agent configuration across many pipelines
- Need to restrict pipeline authors from modifying pod specs
- Using agent injection pattern with compatible images

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

### Issue: Pod fails with "cannot set uid to unmapped user in user namespace"

**Cause:** Using `privileged: false` with SETUID/SETGID capabilities in inline Jenkinsfile pod template.

**Solution:** Choose one of the following approaches:

1. **Use privileged mode** (recommended for inline templates):
   ```yaml
   securityContext:
     privileged: true
   ```
   Requires `scc-privileged-rolebinding.yaml` to be deployed.

2. **Use jenkins-agent-base SCC** (for pre-configured templates):
   - Remove `privileged: true`
   - Ensure pod uses jenkins-agent-base SCC with SETUID/SETGID capabilities
   - Only works with pre-configured pod templates in `values.yaml`

3. **Remove SETUID/SETGID requirements:**
   - Use overlay storage driver if supported
   - Not recommended for OpenShift restricted environments

### Issue: "jenkins-agent not found" or exit code 127 when using rhtap-task-runner

**Cause:** Incorrect pod template configuration or missing container name specification.

**Solution:** Use the single-container pattern with proper container reference:

```yaml
agent {
  kubernetes {
    yaml """
    apiVersion: v1
    kind: Pod
    spec:
      containers:
      - name: 'runner'
        image: 'quay.io/redhat-appstudio/rhtap-task-runner:latest'
        securityContext:
          privileged: true
    """
  }
}
```

Execute build commands by specifying the runner container:

```groovy
container('runner') {
    sh './rhtap/buildah-rhtap.sh'
}
```

**Note:** The Kubernetes plugin automatically handles the Jenkins agent in the background when using inline pod templates.

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
| **Inline pod templates** | Maximum flexibility for images without Java runtime |
| **Privileged SCC** | Required for advanced buildah operations in inline templates |
| **UID 1001 / GID 0** | OpenShift arbitrary UID standard with root group |
| **No UID/GID remapping** | Prevents /etc/subuid errors with chroot isolation |
| **SETUID/SETGID in jenkins-agent-base SCC** | Available for rootless buildah with agent injection (if needed) |
| **rhtap-task-runner image** | Contains buildah, cosign, syft and all RHTAP tools |
| **Single-container pattern** | Runner container with privileged mode, agent handled by Kubernetes plugin |
| **WORKSPACE as HOME** | Required for buildah to write to correct directory |

## References

- [Buildah OpenShift Rootless Tutorial](https://github.com/containers/buildah/blob/main/docs/tutorials/05-openshift-rootless-build.md)
- [Jenkins Helm Chart](https://github.com/jenkinsci/helm-charts/tree/main/charts/jenkins)
- [OpenShift SCC Documentation](https://docs.openshift.com/container-platform/latest/authentication/managing-security-context-constraints.html)
