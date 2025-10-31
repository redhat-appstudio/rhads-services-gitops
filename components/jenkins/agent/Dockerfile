# Jenkins Agent Docker Image with Custom Binaries
# Based on Red Hat UBI 9 with OpenJDK 17 runtime
# Agent injection enabled - no need for Jenkins agent JAR

FROM registry.access.redhat.com/ubi9/openjdk-17-runtime@sha256:6f1b8a5cddbd33ed4727caee5543b81723f81f9f96ed441ad8d19acd9a22c81c

# Set user to root for package installation
USER root

# Install system dependencies and tools
# Note: curl-minimal is already installed in base image, so we skip curl to avoid conflicts
RUN microdnf update -y && \
    microdnf install -y \
        git \
        python3.11 \
        python3.11-pip \
        wget \
        unzip \
        ca-certificates \
        tzdata \
        patch \
        less \
        findutils \
        tar \
        gzip \
        which \
    && microdnf clean all

# Set Python 3.11 as the default python3
RUN alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 && \
    alternatives --set python3 /usr/bin/python3.11 && \
    python3 --version

# Install jq - JSON processor
RUN JQ_VERSION="1.7.1" && \
    ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) JQ_ARCH="amd64" ;; \
        aarch64) JQ_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    curl -L "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${JQ_ARCH}" -o /usr/local/bin/jq && \
    chmod +x /usr/local/bin/jq

# Install yq - YAML processor
RUN YQ_VERSION="v4.44.3" && \
    ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) YQ_ARCH="amd64" ;; \
        aarch64) YQ_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    curl -L "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${YQ_ARCH}" -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Install buildah - Container build tool with capabilities support
RUN microdnf install -y buildah fuse-overlayfs libcap && \
    microdnf clean all

# Configure buildah for rootless operation in OpenShift
# Using vfs storage driver (required for restricted SCC without FUSE support)
# No UID/GID remapping in storage.conf when using BUILDAH_ISOLATION=chroot
RUN mkdir -p /home/jenkins/.config/containers && \
    echo '[storage]' > /home/jenkins/.config/containers/storage.conf && \
    echo 'driver = "vfs"' >> /home/jenkins/.config/containers/storage.conf

# Configure newuidmap/newgidmap capabilities for rootless buildah
# Remove setuid bit and add specific capabilities instead
RUN chmod u-s /usr/bin/new[gu]idmap && \
    setcap cap_setuid+eip /usr/bin/newuidmap && \
    setcap cap_setgid+eip /usr/bin/newgidmap

# Install cosign - Container signing tool
RUN COSIGN_VERSION="v2.4.1" && \
    ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) COSIGN_ARCH="amd64" ;; \
        aarch64) COSIGN_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    curl -L "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${COSIGN_ARCH}" -o /usr/local/bin/cosign && \
    chmod +x /usr/local/bin/cosign

# Install syft - SBOM generation tool
RUN SYFT_VERSION="v1.14.0" && \
    curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin ${SYFT_VERSION}

# Install ec (Enterprise Contract CLI)
RUN EC_VERSION="v0.8.25" && \
    ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) EC_ARCH="amd64" ;; \
        aarch64) EC_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    curl -L "https://github.com/conforma/cli/releases/download/${EC_VERSION}/ec_linux_${EC_ARCH}" -o /usr/local/bin/ec && \
    chmod +x /usr/local/bin/ec

# Create jenkins user with UID 1001 matching OpenShift arbitrary UID and root group (0)
# This matches the reference Dockerfile and OpenShift's security model
ARG user=jenkins
ARG uid=1001
ARG gid=0

RUN groupadd -g 1000 jenkins || true && \
    useradd -d /home/${user} -u ${uid} -g ${gid} -G 1000 -m -s /bin/bash ${user}

# Create /etc/subuid and /etc/subgid for buildah user namespace mapping
# This provides buildah with the subordinate UID/GID ranges needed for rootless operation
# Format: uid:start_id:count (1001:10000:65536 means UID 1001 can use UIDs 10000-75535)
# Using numeric UID instead of username for OpenShift compatibility
RUN touch /etc/subuid /etc/subgid && \
    chmod 644 /etc/subuid /etc/subgid && \
    echo "1001:10000:65536" > /etc/subuid && \
    echo "1001:10000:65536" > /etc/subgid

# Set up workspace directory
RUN mkdir -p /home/jenkins/agent && \
    chown -R jenkins:jenkins /home/jenkins

# Configure containers policy for buildah (allow all images)
RUN mkdir -p /etc/containers && \
    echo '{"default":[{"type":"insecureAcceptAnything"}]}' > /etc/containers/policy.json

# Create buildah storage directory with proper permissions
RUN mkdir -p /home/jenkins/.local/share/containers/storage && \
    chown -R jenkins:jenkins /home/jenkins/.local

# Install git-lfs (Large File Storage)
RUN GIT_LFS_VERSION="3.5.1" && \
    ARCH=$(uname -m) && \
    case ${ARCH} in \
        x86_64) GIT_LFS_ARCH="amd64" ;; \
        aarch64) GIT_LFS_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac && \
    curl -L "https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/git-lfs-linux-${GIT_LFS_ARCH}-v${GIT_LFS_VERSION}.tar.gz" -o /tmp/git-lfs.tar.gz && \
    tar -xzf /tmp/git-lfs.tar.gz -C /tmp && \
    mv /tmp/git-lfs-${GIT_LFS_VERSION}/git-lfs /usr/local/bin/ && \
    chmod +x /usr/local/bin/git-lfs && \
    rm -rf /tmp/git-lfs*

# Set up git-lfs system-wide (as root)
RUN git lfs install --system

# Create symlinks for binaries in /usr/bin (where Jenkins expects them)
RUN ln -sf /usr/local/bin/jq /usr/bin/jq && \
    ln -sf /usr/local/bin/yq /usr/bin/yq && \
    ln -sf /usr/local/bin/syft /usr/bin/syft && \
    ln -sf /usr/local/bin/cosign /usr/bin/cosign && \
    ln -sf /usr/local/bin/ec /usr/bin/ec && \
    ln -sf /usr/local/bin/git-lfs /usr/bin/git-lfs

# Check where buildah and python3 are actually installed and verify symlinks exist
RUN echo "=== Checking actual binary locations ===" && \
    ls -la /usr/bin/buildah || echo "buildah not in /usr/bin/" && \
    ls -la /usr/bin/python3 || echo "python3 not in /usr/bin/" && \
    ls -la /usr/local/bin/ && \
    echo "=== Done checking ==="

# Verify installations
RUN echo "=== Verifying installed binaries ===" && \
    git --version && \
    curl --version && \
    jq --version && \
    yq --version && \
    buildah --version && \
    syft version && \
    cosign version && \
    ec version && \
    python3 --version && \
    java --version && \
    echo "=== All binaries verified ==="

# Verify binaries are accessible from expected locations (using which like Jenkins verification script)
RUN echo "=== Verifying binary locations ===" && \
    which git && \
    which curl && \
    which jq && \
    which yq && \
    which buildah && \
    which syft && \
    which cosign && \
    which ec && \
    which python3 && \
    echo "=== All binary locations verified ==="

# Copy jenkins-agent entrypoint script
COPY jenkins-agent /usr/local/bin/jenkins-agent
RUN chmod +x /usr/local/bin/jenkins-agent

# Switch to jenkins user
USER ${user}

# Set working directory
WORKDIR /home/jenkins

# Set environment variables for Jenkins agent injection
ENV JENKINS_HOME=/home/jenkins
ENV JENKINS_AGENT_WORKDIR=/home/jenkins/agent

# Set buildah environment variables for rootless operation in OpenShift
# _BUILDAH_STARTED_IN_USERNS="" tells buildah it's NOT in a user namespace
# This prevents buildah from trying to create nested user namespaces
ENV _BUILDAH_STARTED_IN_USERNS=""
ENV BUILDAH_ISOLATION=chroot
ENV STORAGE_DRIVER=vfs

# Labels for container metadata
LABEL \
    org.opencontainers.image.vendor="Custom Jenkins Agent" \
    org.opencontainers.image.title="Jenkins Agent with Build Tools" \
    org.opencontainers.image.description="Jenkins agent with git, curl, jq, yq, buildah, syft, cosign, ec, and python3" \
    org.opencontainers.image.version="1.0" \
    org.label-schema.name="Jenkins Agent with Build Tools" \
    org.label-schema.description="Jenkins agent with git, curl, jq, yq, buildah, syft, cosign, ec, and python3" \
    org.label-schema.vcs-url="https://github.com/jenkinsci/docker-agent" \
    org.label-schema.vendor="Custom Jenkins Agent" \
    org.label-schema.schema-version="1.0"

# Use the official Jenkins agent entrypoint script
# This allows using args: ['$(JENKINS_SECRET)', '$(JENKINS_NAME)'] in pod templates
ENTRYPOINT ["/usr/local/bin/jenkins-agent"]
