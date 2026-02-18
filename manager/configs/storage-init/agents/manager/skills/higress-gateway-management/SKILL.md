---
name: higress-gateway-management
description: Manage the Higress AI Gateway via its Console API (consumers, routes, AI providers, MCP servers). Use when creating consumers, configuring routes, or managing AI gateway settings.
---

# Higress AI Gateway Management

## Overview

This skill allows you to manage the Higress AI Gateway via its Console API. The Console API runs at `http://127.0.0.1:8001` and uses **Session Cookie** authentication (NOT Basic Auth).

## Authentication

A session cookie file is stored at the path in `${HIGRESS_COOKIE_FILE}` environment variable. Use it with `curl -b "${HIGRESS_COOKIE_FILE}"`.

If the cookie expires, re-login:

```bash
curl -X POST http://127.0.0.1:8001/session/login \
  -H 'Content-Type: application/json' \
  -c "${HIGRESS_COOKIE_FILE}" \
  -d '{"name": "'"${HICLAW_ADMIN_USER}"'", "password": "'"${HICLAW_ADMIN_PASSWORD}"'"}'
```

## Consumer Management

### List Consumers

```bash
curl -s http://127.0.0.1:8001/v1/consumers -b "${HIGRESS_COOKIE_FILE}" | jq
```

### Create Consumer

```bash
curl -X POST http://127.0.0.1:8001/v1/consumers \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "worker-alice",
    "credentials": [{
      "type": "key-auth",
      "source": "BEARER",
      "values": ["<GENERATED_KEY>"]
    }]
  }'
```

### Update Consumer (e.g., credential rotation with dual-key sliding window)

```bash
# Step 1: GET current consumer
CONSUMER=$(curl -s http://127.0.0.1:8001/v1/consumers/worker-alice -b "${HIGRESS_COOKIE_FILE}")

# Step 2: Add new key alongside old one (dual-key window)
NEW_KEY=$(openssl rand -hex 32)
OLD_KEY=$(echo $CONSUMER | jq -r '.credentials[0].values[0]')
UPDATED=$(echo $CONSUMER | jq --arg new "$NEW_KEY" --arg old "$OLD_KEY" \
  '.credentials[0].values = [$new, $old]')

# Step 3: PUT full object back
curl -X PUT http://127.0.0.1:8001/v1/consumers/worker-alice \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d "$UPDATED"

# Step 4: After Worker confirms new key works, remove old key
FINAL=$(echo $CONSUMER | jq --arg new "$NEW_KEY" '.credentials[0].values = [$new]')
curl -X PUT http://127.0.0.1:8001/v1/consumers/worker-alice \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d "$FINAL"
```

### Delete Consumer

```bash
curl -X DELETE http://127.0.0.1:8001/v1/consumers/worker-alice -b "${HIGRESS_COOKIE_FILE}"
```

## AI Route Management

AI routes are **internal routes** managed via a separate API at `/v1/ai/routes`. They define LLM provider routing with model-level predicates, domain matching, and consumer auth. **Do NOT use `/v1/routes` for AI routes.**

### List AI Routes

```bash
curl -s http://127.0.0.1:8001/v1/ai/routes -b "${HIGRESS_COOKIE_FILE}" | jq
```

### Get AI Route by Name

```bash
curl -s http://127.0.0.1:8001/v1/ai/routes/default-ai-route -b "${HIGRESS_COOKIE_FILE}" | jq
```

### Create AI Route

The system initializes with a `default-ai-route` that has no `modelPredicates` — all model requests go through it. When the human asks to add a **new provider**, create a separate AI route with `modelPredicates` to distinguish which models go where:

```bash
# Example: add a DeepSeek route alongside the existing default route
curl -X POST http://127.0.0.1:8001/v1/ai/routes \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "deepseek-route",
    "domains": ["llm-local.hiclaw.io"],
    "pathPredicate": {"matchType": "PRE", "matchValue": "/", "caseSensitive": false},
    "upstreams": [{"provider": "deepseek", "weight": 100, "modelMapping": {}}],
    "modelPredicates": [{"matchType": "PRE", "matchValue": "deepseek"}],
    "authConfig": {
      "enabled": true,
      "allowedCredentialTypes": ["key-auth"],
      "allowedConsumers": ["manager"]
    }
  }'
```

When adding a new provider route with `modelPredicates`, also update the `default-ai-route` to add matching `modelPredicates` for its own models, so routes are unambiguous.

Key fields:
- **domains**: which domain(s) this AI route serves (e.g. `llm-local.hiclaw.io`)
- **upstreams**: LLM provider(s) with weight and optional model mapping
- **modelPredicates**: match models by prefix/exact/regex (e.g. `{"matchType":"PRE","matchValue":"deepseek"}` routes all `deepseek*` models). Omit when only one route exists
- **authConfig**: consumer-level access control

### Update AI Route (e.g., grant Worker access)

```bash
# Step 1: GET current AI route
AI_ROUTE=$(curl -s http://127.0.0.1:8001/v1/ai/routes/default-ai-route -b "${HIGRESS_COOKIE_FILE}")

# Step 2: Add worker-alice to allowedConsumers
UPDATED=$(echo $AI_ROUTE | jq '.authConfig.allowedConsumers += ["worker-alice"]')

# Step 3: PUT full object (AI Route has "version" field, include it)
curl -X PUT http://127.0.0.1:8001/v1/ai/routes/default-ai-route \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d "$UPDATED"
```

### Delete AI Route

```bash
curl -X DELETE http://127.0.0.1:8001/v1/ai/routes/<route-name> -b "${HIGRESS_COOKIE_FILE}"
```

## LLM Provider Configuration

### List AI Providers

```bash
curl -s http://127.0.0.1:8001/v1/ai/providers -b "${HIGRESS_COOKIE_FILE}" | jq
```

### Create Provider

```bash
# Qwen (native type)
curl -X POST http://127.0.0.1:8001/v1/ai/providers \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "qwen", "name": "qwen",
    "tokens": ["<API_KEY>"], "protocol": "openai/v1",
    "tokenFailoverConfig": {"enabled": false},
    "rawConfigs": {"qwenEnableSearch": false, "qwenEnableCompatible": true, "qwenFileIds": []}
  }'

# OpenAI-compatible (generic)
curl -X POST http://127.0.0.1:8001/v1/ai/providers \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d '{
    "type": "openai", "name": "my-provider",
    "tokens": ["<API_KEY>"], "protocol": "openai/v1",
    "modelMapping": {},
    "rawConfigs": {"apiUrl": "https://api.example.com/v1"}
  }'
```

### Update Provider (e.g., rotate API keys)

```bash
# GET-modify-PUT pattern (provider has "version" field)
PROVIDER=$(curl -s http://127.0.0.1:8001/v1/ai/providers/qwen -b "${HIGRESS_COOKIE_FILE}")
UPDATED=$(echo $PROVIDER | jq '.tokens = ["<NEW_KEY>"]')
curl -X PUT http://127.0.0.1:8001/v1/ai/providers/qwen \
  -b "${HIGRESS_COOKIE_FILE}" \
  -H 'Content-Type: application/json' \
  -d "$UPDATED"
```

## MCP Server Management

For creating, updating, listing, and deleting MCP Servers, as well as managing consumer access to MCP tools, see the **`mcp-server-management`** skill.

## Important Notes

- **Auth Plugin Activation**: First configuration takes ~40s, subsequent changes ~10s
- **Version field**: AI Routes and Providers have a `version` field. Always GET before PUT to get the latest version.
- **Consumer version**: Consumers do NOT have a `version` field
- **MCP Server**: See `mcp-server-management` skill for full details on creating and managing MCP servers
