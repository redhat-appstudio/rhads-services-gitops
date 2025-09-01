# Jenkins Agent Image Build

This directory contains the Dockerfile for the custom Jenkins agent image.

## Build Instructions

### Single Architecture Build

```bash
cd components/jenkins/agent

# Build for Linux AMD64 (OpenShift target platform)
podman build --platform linux/amd64 -t quay.io/rhtap/tssc-jenkins-agent:latest -f Dockerfile .

# Push to registry
podman push quay.io/rhtap/tssc-jenkins-agent:latest
```

### Multi-Architecture Build (Recommended)

```bash
cd components/jenkins/agent

# Build multi-arch manifest for AMD64 and ARM64
PLATFORMS=linux/amd64,linux/arm64
podman build --jobs=2 --platform=$PLATFORMS --manifest quay.io/rhtap/tssc-jenkins-agent:latest -f Dockerfile .

# Push the manifest list (includes all architectures)
podman manifest push --all quay.io/rhtap/tssc-jenkins-agent:latest
```

**Note**:
- The `--platform` flag ensures the image is built for the target architecture, regardless of build host OS (macOS ARM/Intel, Linux, Windows)
- Multi-arch builds create a manifest list that automatically selects the correct image for each platform
- `--jobs=4` enables parallel builds for faster execution
- Use `--all` with `manifest push` to push all architecture variants

## Why This Directory?

The `agent/` directory is separate from the main jenkins component to:
- Prevent ArgoCD from processing the Dockerfile as a Kubernetes resource
- Keep build-related files isolated from deployment manifests
- Provide a clean separation of concerns

## Image Contents

- **Base**: UBI9 OpenJDK 17 runtime
- **Python**: 3.11 (required for hashlib.file_digest)
- **Buildah**: Rootless container build tool
- **Tools**: syft, cosign, ec, jq, yq, git-lfs

See the main [Jenkins README](../README.md) for full deployment documentation.
