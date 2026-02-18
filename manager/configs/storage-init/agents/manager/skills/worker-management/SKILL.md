---
name: worker-management
description: Manage the full lifecycle of Worker Agents (create, configure, monitor, credential rotation, reset). Use when the human admin requests creating a new worker, rotating credentials, or resetting a worker.
---

# Worker Management

## Overview

This skill allows you to manage the full lifecycle of Worker Agents: creation, configuration, monitoring, credential rotation, and reset. Workers are lightweight containers that connect to the Manager via Matrix and use the centralized file system.

## Create a Worker

### Step 1: Write SOUL.md

Write the Worker's identity file based on the human admin's description:

```bash
mkdir -p ~/hiclaw-fs/agents/<WORKER_NAME>
cat > ~/hiclaw-fs/agents/<WORKER_NAME>/SOUL.md << 'EOF'
# Worker Agent - <WORKER_NAME>
... (role, skills, communication rules, security rules, etc.)
EOF
```

### Step 2: Run create-worker script

The script handles everything: Matrix registration, room creation, Higress consumer, AI/MCP authorization, config generation, MinIO sync, and container startup.

```bash
bash /opt/hiclaw/scripts/create-worker.sh --name <WORKER_NAME> [--model <MODEL_ID>] [--mcp-servers s1,s2] [--remote]
```

**Parameters**:
- `--name` (required): Worker name
- `--model`: optional, bare model name (e.g. `qwen3.5-plus`). Defaults to `${HICLAW_DEFAULT_MODEL}`
- `--mcp-servers`: optional, comma-separated MCP server names. Defaults to all existing MCP servers
- `--remote`: force output install command instead of starting container locally

**Deployment behavior** (without `--remote`):
- If container socket is available: auto-starts Worker container locally

、÷- If no socket: falls back to outputting install command

The script outputs a JSON result after `---RESULT---`:

```json
{
  "worker_name": "xiaozhang",
  "matrix_user_id": "@xiaozhang:matrix-local.hiclaw.io:8080",
  "room_id": "!abc:matrix-local.hiclaw.io:8080",
  "consumer": "worker-xiaozhang",
  "mode": "local",
  "container_id": "abc123...",
  "status": "started"
}
```

Report the result to the human admin. If `status` is `"pending_install"`, provide the `install_cmd` from the JSON output. Also remind the admin that for remote deployment, the Worker machine must be able to resolve these domains to the Manager's IP (via DNS or `/etc/hosts`):

- `${HICLAW_MATRIX_DOMAIN}` (Matrix homeserver, e.g. `matrix-local.hiclaw.io`)
- `${HICLAW_AI_GATEWAY_DOMAIN}` (AI Gateway, e.g. `llm-local.hiclaw.io`)
- `${HICLAW_FS_DOMAIN}` (MinIO file system, e.g. `fs-local.hiclaw.io`)

For local deployment these are auto-resolved via container ExtraHosts.

### Post-creation verification

After a local deployment (`mode: "local"`), verify the Worker is running:

```bash
bash -c 'source /opt/hiclaw/scripts/container-api.sh && container_status_worker "<WORKER_NAME>"'
bash -c 'source /opt/hiclaw/scripts/container-api.sh && container_logs_worker "<WORKER_NAME>" 20'
```

## Monitor Workers

### Heartbeat Check (automated every 15 minutes)

The heartbeat prompt triggers automatically. When it fires:

1. Check each Worker's Room for recent messages
2. For Workers with assigned tasks and no completion notification, ask for status in their Room
3. Check credential expiration
4. Assess capacity vs pending tasks

### Manual Status Check

```bash
# Check if a Worker container is running (Worker should be sending heartbeat-like messages)
# Check the Worker's Room for recent activity:
curl -s "http://127.0.0.1:6167/_matrix/client/v3/rooms/<ROOM_ID>/messages?dir=b&limit=5" \
  -H "Authorization: Bearer <MANAGER_TOKEN>" | jq '.chunk[].content.body'
```

## Credential Rotation

Uses dual-key sliding window to prevent downtime:

1. Generate new key
2. Add new key alongside old key (Consumer has 2 values)
3. Update Worker's config file in MinIO (`~/hiclaw-fs/agents/<WORKER_NAME>/openclaw.json`)
4. **Notify the Worker in their Room**: send a message asking them to sync config (e.g., "Please sync your configuration now — credentials have been updated.")
5. Worker runs `hiclaw-sync` and OpenClaw hot-reloads (~300ms after file change)
6. Verify Worker can auth with new key
7. Remove old key from Consumer

See `higress-gateway-management` SKILL.md for the exact API calls.

## Reset a Worker

1. Revoke the Worker's Higress Consumer (or update credentials)
2. Remove Worker from AI route auth configs (`/v1/ai/routes` — GET, remove from allowedConsumers, PUT)
3. Remove Worker from MCP Server consumer lists (`/v1/mcpServer/consumers`)
4. Delete Worker's config directory: `rm -rf ~/hiclaw-fs/agents/<WORKER_NAME>/`
5. Re-create: write a new SOUL.md and run `create-worker.sh` again (the script handles re-registration gracefully)

## Important Notes

- Workers are **stateless containers** -- all state is in MinIO. Resetting a Worker just means recreating its config files
- Worker Matrix accounts persist in Tuwunel (cannot be deleted via API). Reuse same username on reset
- OpenClaw config hot-reload: file-watch (~300ms) or `config.patch` API
- **File sync**: after writing any file that a Worker (or another Worker) needs to read, always notify the target Worker via Matrix to run `hiclaw-sync`. This applies to config updates, credential rotation, task briefs, shared data, and cross-Worker collaboration artifacts. Workers have a `file-sync` skill for this. Background periodic sync (every 5 minutes) serves as fallback only
