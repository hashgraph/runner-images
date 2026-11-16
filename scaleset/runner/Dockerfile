# Source: https://github.com/dotnet/dotnet-docker
ARG BASE_OS_VERSION=jammy

# Base images are pinned by digest (one stage per supported BASE_OS_VERSION) so Dependabot can track them.
# BuildKit only pulls the stage selected by BASE_OS_VERSION.
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-jammy@sha256:01e4e9b15b57a2e8012a872dfe52ca333e0ee8a18e5a9bbd16830c86b0b232b0 AS base-jammy
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-noble@sha256:7745316518f2abec3e133889558c2e8d4b616d3ca138db4c5b8c0914a0af3919 AS base-noble
FROM mcr.microsoft.com/dotnet/runtime-deps:8.0-bookworm-slim@sha256:54c5e25d41d6df433e520750bacfa4eed1f664140cd36b37c189dd6c6df33d79 AS base-bookworm-slim

FROM base-${BASE_OS_VERSION} AS build

ARG TARGET_OS
ARG TARGET_ARCH
ARG RUNNER_VERSION
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.8.1
ARG DOCKER_VERSION=29.10.0
ARG BUILDX_VERSION=0.39.0

RUN apt update -y && apt install curl unzip -y

WORKDIR /actions-runner
RUN export RUNNER_ARCH=${TARGET_ARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export RUNNER_ARCH=x64 ; fi \
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-${TARGET_OS}-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

RUN export RUNNER_ARCH=${TARGET_ARCH} \
    && if [ "$RUNNER_ARCH" = "amd64" ]; then export DOCKER_ARCH=x86_64 ; fi \
    && if [ "$RUNNER_ARCH" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && curl -fLo docker.tgz https://download.docker.com/${TARGET_OS}/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && rm -rf docker.tgz \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fLo /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${TARGET_ARCH}" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

FROM base-${BASE_OS_VERSION}

ARG BASE_OS_VERSION

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ImageOS=${BASE_OS_VERSION}

SHELL ["/bin/bash", "-c"]

# 'gpg-agent' and 'software-properties-common' are needed for the 'add-apt-repository' command that follows
RUN apt update -y \
    && apt install -y --no-install-recommends sudo lsb-release gpg-agent software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Configure git-core/ppa based on guidance here:  https://git-scm.com/download/linux
RUN if [[ "$(lsb_release -i | awk '{print $3;}')" == "Ubuntu" ]]; then \
      add-apt-repository ppa:git-core/ppa; \
      apt update -y; \
    fi

RUN adduser --disabled-password --gecos "" --uid 1001 runner \
    && groupadd docker --gid 123 \
    && usermod -aG sudo runner \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers \
    && echo "Defaults env_keep += \"DEBIAN_FRONTEND\"" >> /etc/sudoers

WORKDIR /home/runner

COPY --chown=runner:docker --from=build /actions-runner .
COPY --from=build /usr/local/lib/docker/cli-plugins/docker-buildx /usr/local/lib/docker/cli-plugins/docker-buildx

RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker

#########################################
## Begin Tool Cache Customization      ##
#########################################
COPY --link --chown=1001:123 --chmod=777 tools /home/runner/_work/_tool
#########################################
## End Tool Cache Customization        ##
#########################################

#########################################
## Begin OS Software Customizations    ##
#########################################
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends \
    git \
    make \
    wget \
    gnupg2 \
    tree \
    curl \
    unzip \
    zip \
    gzip \
    jq \
    skopeo \
    python3-pip \
    build-essential \
    htop \
    psmisc \
    openssh-client

ARG TARGET_ARCH
ARG JFROG_CLI_VERSION=2.133.0
RUN JF_URL="https://releases.jfrog.io/artifactory/jfrog-cli/v2-jf/${JFROG_CLI_VERSION}/jfrog-cli-linux-${TARGET_ARCH}/jf" \
    && curl -fsSLo /tmp/jf "${JF_URL}" \
    && curl -fsSLo /tmp/jf.sha256 "${JF_URL}.sha256" \
    && echo "$(awk 'NR==1 {print $1}' /tmp/jf.sha256)  /tmp/jf" | sha256sum -c - \
    && install -m 755 /tmp/jf /usr/local/bin/jf \
    && rm -f /tmp/jf /tmp/jf.sha256

ARG TASK_VERSION=3.54.0
RUN TASK_URL="https://github.com/go-task/task/releases/download/v${TASK_VERSION}" \
    && curl -fsSLo /tmp/task.tar.gz "${TASK_URL}/task_linux_${TARGET_ARCH}.tar.gz" \
    && curl -fsSLo /tmp/task_checksums.txt "${TASK_URL}/task_checksums.txt" \
    && echo "$(awk -v f="task_linux_${TARGET_ARCH}.tar.gz" '$2 == f {print $1}' /tmp/task_checksums.txt)  /tmp/task.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/task.tar.gz --no-same-owner -C /usr/local/bin task \
    && chmod 755 /usr/local/bin/task \
    && rm -f /tmp/task.tar.gz /tmp/task_checksums.txt

# semver-tool publishes no release checksums; pin the commit (tag 3.4.0) and the script's SHA-256.
ARG SEMVER_TOOL_COMMIT=837ad91179c4126e3b7ff73c35091d5ef561d9a3
ARG SEMVER_TOOL_SHA256=1ff4a97e4d1e389f6f034f7464ac4365f1be2d900e2dc2121e24a6dc239e8991
RUN curl -fsSLo /usr/local/bin/semver \
        "https://raw.githubusercontent.com/fsaintjacques/semver-tool/${SEMVER_TOOL_COMMIT}/src/semver" \
    && echo "${SEMVER_TOOL_SHA256}  /usr/local/bin/semver" | sha256sum -c - \
    && chmod 755 /usr/local/bin/semver

ARG GH_CLI_VERSION=2.104.0
RUN export ARCH=${TARGET_ARCH} \
    && if [ "${ARCH}" = "i386" ]; then export ARCH=386 ; fi \
    && curl -sL https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${ARCH}.tar.gz \
        | tar -xz --wildcards --strip-components=2 -C /usr/local/bin "*/bin/gh" \
    && chmod +x /usr/local/bin/gh

ARG YQ_CLI_VERSION=4.54.3
RUN export ARCH=${TARGET_ARCH} \
    && if [ "${ARCH}" = "i386" ]; then export ARCH=386 ; fi \
    && curl -fLo /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/v${YQ_CLI_VERSION}/yq_linux_${ARCH}" \
    && chmod +x /usr/local/bin/yq

ARG COMPOSE_VERSION=5.7.1
RUN export RUNNER_ARCH=${TARGET_ARCH} \
    && if [ "${RUNNER_ARCH}" = "amd64" ]; then export DOCKER_ARCH=x86_64 ; fi \
    && if [ "${RUNNER_ARCH}" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fLo /usr/local/lib/docker/cli-plugins/docker-compose \
        "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${DOCKER_ARCH}" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ansible-core 2.22 requires Python >= 3.13, which none of the base OS images ship. A pinned, checksum-verified
# uv installs a standalone CPython and ansible-core under /opt/uv (entry points in /usr/local/bin); uv itself
# is removed afterwards.
ARG UV_VERSION=0.13.8
ARG ANSIBLE_PYTHON_VERSION=3.13.18
ARG ANSIBLE_CORE_VERSION=2.22.0
RUN export UV_ARCH=${TARGET_ARCH} \
    && if [ "${UV_ARCH}" = "amd64" ]; then export UV_ARCH=x86_64 ; fi \
    && if [ "${UV_ARCH}" = "arm64" ]; then export UV_ARCH=aarch64 ; fi \
    && UV_ASSET="uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" \
    && UV_URL="https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${UV_ASSET}" \
    && curl -fsSLo "/tmp/${UV_ASSET}" "${UV_URL}" \
    && curl -fsSLo "/tmp/${UV_ASSET}.sha256" "${UV_URL}.sha256" \
    && (cd /tmp && sha256sum -c "${UV_ASSET}.sha256") \
    && tar -xzf "/tmp/${UV_ASSET}" --no-same-owner --strip-components=1 -C /tmp "uv-${UV_ARCH}-unknown-linux-gnu/uv" \
    && UV_PYTHON_INSTALL_DIR=/opt/uv/python UV_TOOL_DIR=/opt/uv/tools UV_TOOL_BIN_DIR=/usr/local/bin \
       UV_PYTHON_PREFERENCE=only-managed UV_NO_CACHE=1 \
       /tmp/uv tool install --python "${ANSIBLE_PYTHON_VERSION}" "ansible-core==${ANSIBLE_CORE_VERSION}" \
    && rm -f /tmp/uv "/tmp/${UV_ASSET}" "/tmp/${UV_ASSET}.sha256"

RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/*

#########################################
## End OS Software Customizations      ##
#########################################

USER runner
