# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

# Base image pinned by digest (multi-arch index). Renovate keeps the digest current.
FROM node:24-bookworm-slim@sha256:01d566e8d94d8c619591d78652babfccd3c6992a3dffa9ed5ab39e11cf6c70e9

# Single source of truth for the Pi version. Release tags (v<PI_VERSION>-<rev>) must match it.
# renovate: datasource=npm depName=@earendil-works/pi-coding-agent
ARG PI_VERSION=1.5.2

LABEL org.opencontainers.image.source="https://github.com/pfrybar/pi-agent" \
      org.opencontainers.image.title="pi-agent" \
      org.opencontainers.image.description="Pi coding agent (@earendil-works/pi-coding-agent) packaged for headless, sandboxed runs" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${PI_VERSION}"

# Debian packages track the pinned base image snapshot; see .hadolint.yaml for DL3008.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      fd-find \
      git \
      ripgrep \
 && ln -s /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# --ignore-scripts: no install-time lifecycle scripts from the dependency tree.
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" \
 && npm cache clean --force \
 && mkdir -p /workspace /home/node/.pi/agent \
 && chown -R node:node /workspace /home/node/.pi

# PI_CODING_AGENT_DIR can be overridden (e.g. to a mounted emptyDir in Kubernetes).
# Version checks and install telemetry are off by default for unattended runs; override if wanted.
ENV PI_CODING_AGENT_DIR=/home/node/.pi/agent \
    PI_SKIP_VERSION_CHECK=1 \
    PI_TELEMETRY=0

# Numeric UID/GID of the base image's `node` user, so Kubernetes `runAsNonRoot` can verify it.
USER 1000:1000
WORKDIR /workspace

ENTRYPOINT ["pi"]
