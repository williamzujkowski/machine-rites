FROM ubuntu:24.04

# Metadata
LABEL maintainer="machine-rites"
LABEL description="Ubuntu 24.04 testing environment for machine-rites"
LABEL version="1.0.0"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV USER=testuser
ENV HOME=/home/testuser
ENV SHELL=/bin/bash

# Update package list and install essential packages
RUN apt-get update && apt-get install -y \
    bash \
    curl \
    git \
    gnupg \
    make \
    sudo \
    wget \
    ca-certificates \
    software-properties-common \
    apt-transport-https \
    build-essential \
    vim \
    nano \
    tree \
    jq \
    unzip \
    zip \
    tar \
    gzip \
    systemd \
    systemd-sysv \
    locales \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Generate locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Create test user with sudo access
RUN useradd -m -s /bin/bash -G sudo ${USER} && \
    echo "${USER}:testpass" | chpasswd && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p ${HOME}/.config && \
    chown -R ${USER}:${USER} ${HOME}

# Create directories for testing
RUN mkdir -p /opt/machine-rites && \
    chown -R ${USER}:${USER} /opt/machine-rites

# Install additional development tools
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    nodejs \
    npm \
    shellcheck \
    bats \
    && rm -rf /var/lib/apt/lists/*

# Set up working directory
WORKDIR /opt/machine-rites

# Switch to test user
USER ${USER}

# Set up user environment
RUN echo 'export PATH=$PATH:/home/testuser/.local/bin' >> ${HOME}/.bashrc && \
    echo 'export MACHINE_RITES_TEST=true' >> ${HOME}/.bashrc && \
    echo 'cd /opt/machine-rites' >> ${HOME}/.bashrc

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD which bash && which git && which make || exit 1

# Default command
CMD ["/bin/bash"]