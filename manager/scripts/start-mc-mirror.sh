#!/bin/bash
# start-mc-mirror.sh - Initialize MinIO storage and start bidirectional file sync

source /opt/hiclaw/scripts/base.sh
waitForService "MinIO" "127.0.0.1" 9000

# Configure mc alias (local access, not through Higress)
mc alias set hiclaw http://127.0.0.1:9000 "${HICLAW_MINIO_USER:-${HICLAW_ADMIN_USER:-admin}}" "${HICLAW_MINIO_PASSWORD:-${HICLAW_ADMIN_PASSWORD:-admin}}"

# Create default bucket
mc mb hiclaw/hiclaw-storage --ignore-existing

# Initialize directory structure from template
mc cp /opt/hiclaw/configs/storage-init/ hiclaw/hiclaw-storage/ --recursive

# Create local mirror directory
mkdir -p ~/hiclaw-fs

# Initial full sync to local
mc mirror hiclaw/hiclaw-storage/ ~/hiclaw-fs/ --overwrite

# Signal that initialization is complete
touch ~/hiclaw-fs/.initialized

log "MinIO storage initialized and synced to ~/hiclaw-fs/"

# Start bidirectional sync
# Local -> Remote: real-time watch (filesystem notify)
mc mirror --watch ~/hiclaw-fs/ hiclaw/hiclaw-storage/ --overwrite &
LOCAL_TO_REMOTE_PID=$!

log "Local->Remote sync started (PID: ${LOCAL_TO_REMOTE_PID})"

# Remote -> Local: periodic pull every 5 minutes (aligned with heartbeat)
while true; do
    sleep 300
    mc mirror hiclaw/hiclaw-storage/ ~/hiclaw-fs/ --overwrite --newer-than "5m" 2>/dev/null || true
done
