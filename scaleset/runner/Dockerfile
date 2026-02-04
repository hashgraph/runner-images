# Source: https://github.com/dotnet/dotnet-docker
ARG BASE_OS_VERSION=jammy
ARG DOTNET_RUNTIME_VERSION=8.0
FROM mcr.microsoft.com/dotnet/runtime-deps:${DOTNET_RUNTIME_VERSION}-${BASE_OS_VERSION} AS build

ARG TARGET_OS
ARG TARGET_ARCH
ARG RUNNER_VERSION
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.8.0
ARG DOCKER_VERSION=29.1.3
ARG BUILDX_VERSION=0.30.1

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

FROM mcr.microsoft.com/dotnet/runtime-deps:${DOTNET_RUNTIME_VERSION}-${BASE_OS_VERSION}

ARG BASE_OS_VERSION

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1
ENV ImageOS=${BASE_OS_VERSION}

# 'gpg-agent' and 'software-properties-common' are needed for the 'add-apt-repository' command that follows
RUN apt update -y \
    && apt install -y --no-install-recommends sudo lsb-release gpg-agent software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Configure git-core/ppa based on guidance here:  https://git-scm.com/download/linux
RUN if [ "$(lsb_release -i | awk '{print $3;}')" == "Ubuntu" ]; then \
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

RUN curl -fL https://install-cli.jfrog.io | sh \
    && sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin \
    && curl -L -o /usr/local/bin/semver https://raw.githubusercontent.com/fsaintjacques/semver-tool/master/src/semver \
    && chmod +x /usr/local/bin/semver

ARG TARGET_ARCH
ARG GH_CLI_VERSION=2.86.0
RUN export ARCH=${TARGET_ARCH} \
    && if [ "${ARCH}" = "i386" ]; then export ARCH=386 ; fi \
    && curl -sL https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${ARCH}.tar.gz \
        | tar -xz --wildcards --strip-components=2 -C /usr/local/bin "*/bin/gh" \
    && chmod +x /usr/local/bin/gh

ARG YQ_CLI_VERSION=4.52.2
RUN export ARCH=${TARGET_ARCH} \
    && if [ "${ARCH}" = "i386" ]; then export ARCH=386 ; fi \
    && curl -fLo /usr/local/bin/yq \
        "https://github.com/mikefarah/yq/releases/download/v${YQ_CLI_VERSION}/yq_linux_${ARCH}" \
    && chmod +x /usr/local/bin/yq

ARG COMPOSE_VERSION=2.40.3
RUN export RUNNER_ARCH=${TARGET_ARCH} \
    && if [ "${RUNNER_ARCH}" = "amd64" ]; then export DOCKER_ARCH=x86_64 ; fi \
    && if [ "${RUNNER_ARCH}" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fLo /usr/local/lib/docker/cli-plugins/docker-compose \
        "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${DOCKER_ARCH}" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

RUN if [ "$(lsb_release -i | awk '{print $3;}')" == "Debian" || "$(lsb_release -c | awk '{print $2;}')" == "noble" ]; then \
      apt-get install -y --no-install-recommends ansible; \
    else \
      pip3 install ansible; \
    fi

RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/*

#########################################
## End OS Software Customizations      ##
#########################################

USER runner
