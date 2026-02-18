#!/bin/bash
# worker-entrypoint.sh - Worker Agent startup
# Pulls config from centralized file system, starts file sync, launches OpenClaw.

set -e

WORKER_NAME="${HICLAW_WORKER_NAME:?HICLAW_WORKER_NAME is required}"
FS_ENDPOINT="${HICLAW_FS_ENDPOINT:?HICLAW_FS_ENDPOINT is required}"
FS_ACCESS_KEY="${HICLAW_FS_ACCESS_KEY:?HICLAW_FS_ACCESS_KEY is required}"
FS_SECRET_KEY="${HICLAW_FS_SECRET_KEY:?HICLAW_FS_SECRET_KEY is required}"

log() {
    echo "[hiclaw-worker $(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# ============================================================
# Step 1: Configure mc alias for centralized file system
# ============================================================
log "Configuring mc alias..."
mc alias set hiclaw "${FS_ENDPOINT}" "${FS_ACCESS_KEY}" "${FS_SECRET_KEY}"

# ============================================================
# Step 2: Pull Worker config from centralized storage
# ============================================================
WORKSPACE="/root/workspace"
mkdir -p "${WORKSPACE}"

log "Pulling Worker config from centralized storage..."
mc mirror "hiclaw/hiclaw-storage/agents/${WORKER_NAME}/" "${WORKSPACE}/" --overwrite

# Also pull shared knowledge
mc mirror "hiclaw/hiclaw-storage/shared/" "${WORKSPACE}/shared/" --overwrite 2>/dev/null || true

# Verify essential files exist, retry if sync is still in progress
RETRY=0
while [ ! -f "${WORKSPACE}/openclaw.json" ] || [ ! -f "${WORKSPACE}/SOUL.md" ]; do
    RETRY=$((RETRY + 1))
    if [ "${RETRY}" -gt 6 ]; then
        log "ERROR: openclaw.json or SOUL.md not found after retries. Manager may not have created this Worker's config yet."
        exit 1
    fi
    log "Waiting for config files to appear in MinIO (attempt ${RETRY}/6)..."
    sleep 5
    mc mirror "hiclaw/hiclaw-storage/agents/${WORKER_NAME}/" "${WORKSPACE}/" --overwrite 2>/dev/null || true
done

# Symlink to default OpenClaw config path so CLI commands find the config
mkdir -p /root/.openclaw
ln -sf "${WORKSPACE}/openclaw.json" /root/.openclaw/openclaw.json

# Copy skill templates
cp -r /opt/hiclaw/configs/skills/* "${WORKSPACE}/skills/" 2>/dev/null || true

log "Worker config pulled successfully"

# ============================================================
# Step 3: Start bidirectional mc mirror sync
# ============================================================

# Local -> Remote: real-time watch
mc mirror --watch "${WORKSPACE}/" "hiclaw/hiclaw-storage/agents/${WORKER_NAME}/" --overwrite &
LOCAL_PID=$!
log "Local->Remote sync started (PID: ${LOCAL_PID})"

# Remote -> Local: periodic pull every 5 minutes
(
    while true; do
        sleep 300
        mc mirror "hiclaw/hiclaw-storage/agents/${WORKER_NAME}/" "${WORKSPACE}/" --overwrite --newer-than "5m" 2>/dev/null || true
        mc mirror "hiclaw/hiclaw-storage/shared/" "${WORKSPACE}/shared/" --overwrite --newer-than "5m" 2>/dev/null || true
    done
) &
REMOTE_PID=$!
log "Remote->Local sync started (PID: ${REMOTE_PID})"

# ============================================================
# Step 4: Configure mcporter (MCP tool CLI)
# ============================================================
if [ -f "${WORKSPACE}/mcporter-servers.json" ]; then
    log "Configuring mcporter with MCP Server endpoints..."
    export MCPORTER_CONFIG="${WORKSPACE}/mcporter-servers.json"
fi

# ============================================================
# Step 5: Launch OpenClaw Worker Agent
# ============================================================
log "Starting Worker Agent: ${WORKER_NAME}"
export OPENCLAW_CONFIG_PATH="${WORKSPACE}/openclaw.json"
exec openclaw gateway run --verbose --force
