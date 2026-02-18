# ============================================================
# HiClaw Worker Agent - Lightweight Container
# ============================================================
# Contains: OpenClaw (Agent framework) + mc (MinIO Client) + mcporter (MCP CLI)
# Workers are stateless -- all config/state stored in centralized MinIO.
#
# Build args:
#   HIGRESS_REGISTRY  - base image registry (default: cn-hangzhou)
#   APT_MIRROR        - APT mirror host (default: mirrors.aliyun.com, set to empty to use official)
# ============================================================

ARG HIGRESS_REGISTRY=higress-registry.cn-hangzhou.cr.aliyuncs.com

# ============ Stage 1: mc (MinIO Client) ============
FROM ${HIGRESS_REGISTRY}/higress/mc:20260216 AS mc

# ============ Stage 2: OpenClaw + mcporter build ============
FROM ${HIGRESS_REGISTRY}/higress/node:20-slim AS openclaw-build

ARG APT_MIRROR=mirrors.aliyun.com
RUN if [ -n "${APT_MIRROR}" ]; then \
        sed -i "s|deb.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
        sed -i "s|deb.debian.org|${APT_MIRROR}|g" /etc/apt/sources.list 2>/dev/null || true; \
    fi && \
    apt-get update && apt-get install -y git python3 make g++ curl && \
    npm install -g pnpm n && n 22 && \
    hash -r && node --version

RUN git clone https://github.com/johnlanni/openclaw.git /opt/openclaw && \
    cd /opt/openclaw && git checkout fix-event-too-old

RUN cd /opt/openclaw && pnpm install && pnpm build

RUN npm install -g mcporter

# ============ Final Image ============
FROM ${HIGRESS_REGISTRY}/higress/ubuntu:24.04

ARG APT_MIRROR=mirrors.aliyun.com
RUN if [ -n "${APT_MIRROR}" ]; then \
        sed -i "s|archive.ubuntu.com|${APT_MIRROR}|g; s|security.ubuntu.com|${APT_MIRROR}|g" \
            /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || \
        sed -i "s|archive.ubuntu.com|${APT_MIRROR}|g; s|security.ubuntu.com|${APT_MIRROR}|g" \
            /etc/apt/sources.list 2>/dev/null || true; \
    fi && \
    apt-get update && apt-get install -y \
    curl jq git python3 python3-pip \
    openssh-client ca-certificates procps \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 from build stage (Ubuntu apt only has 18.x which lacks --disable-warning support)
COPY --from=openclaw-build /usr/local/bin/node /usr/local/bin/node
COPY --from=openclaw-build /usr/local/bin/npm /usr/local/bin/npm
COPY --from=openclaw-build /usr/local/bin/npx /usr/local/bin/npx
COPY --from=openclaw-build /usr/local/lib/node_modules /usr/local/lib/node_modules

# mc (MinIO Client)
COPY --from=mc /usr/bin/mc /usr/local/bin/mc

# OpenClaw
COPY --from=openclaw-build /opt/openclaw /opt/openclaw

# mcporter
COPY --from=openclaw-build /usr/local/lib/node_modules/mcporter /usr/local/lib/node_modules/mcporter
COPY --from=openclaw-build /usr/local/bin/mcporter /usr/local/bin/mcporter

# Ensure openclaw binary is on PATH and config is found
ENV PATH="/opt/openclaw/packages/clawdbot/node_modules/.bin:${PATH}"
ENV OPENCLAW_CONFIG_PATH="/root/workspace/openclaw.json"

# Worker entrypoint and configs
COPY scripts/ /opt/hiclaw/scripts/
COPY configs/ /opt/hiclaw/configs/
RUN chmod +x /opt/hiclaw/scripts/*.sh && \
    ln -s /opt/hiclaw/scripts/hiclaw-sync.sh /usr/local/bin/hiclaw-sync

# Worker workspace
RUN mkdir -p /root/workspace

WORKDIR /root/workspace

ENTRYPOINT ["/opt/hiclaw/scripts/worker-entrypoint.sh"]
