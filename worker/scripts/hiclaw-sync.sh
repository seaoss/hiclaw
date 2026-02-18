#!/bin/sh
# hiclaw-sync.sh - Pull latest config from centralized storage
# Called by the Worker agent when Manager notifies of config updates.

WORKER_NAME="${HICLAW_WORKER_NAME:?HICLAW_WORKER_NAME is required}"
WORKSPACE="${HICLAW_WORKSPACE:-/root/workspace}"

mc mirror "hiclaw/hiclaw-storage/agents/${WORKER_NAME}/" "${WORKSPACE}/" --overwrite 2>&1
mc mirror "hiclaw/hiclaw-storage/shared/" "${WORKSPACE}/shared/" --overwrite 2>/dev/null || true

echo "Config sync completed at $(date)"
