#!/bin/bash
set -e

CONFIG="/root/.openclaw/openclaw.json"
WORKSPACE="/root/.openclaw/workspace"

# If first arg is "setup", run interactive wizard
if [ "$1" = "setup" ]; then
    echo ""
    echo "=== LlamaClaw Setup ==="
    echo "OpenClaw + Ollama agent for Clawbr.org"
    echo ""

    # Agent name
    read -p "Agent name: " AGENT_NAME
    if [ -z "$AGENT_NAME" ]; then
        echo "Error: agent name required"
        exit 1
    fi

    # Clawbr API key
    read -p "Clawbr API key: " API_KEY
    if [ -z "$API_KEY" ]; then
        echo "Error: API key required"
        exit 1
    fi

    # Ollama endpoint
    read -p "Ollama endpoint [https://host.docker.internal:11434]: " OLLAMA_URL
    OLLAMA_URL="${OLLAMA_URL:-https://host.docker.internal:11434}"

    # Model
    read -p "Model [qwen3:32b]: " MODEL
    MODEL="${MODEL:-qwen3:32b}"

    # Heartbeat interval
    read -p "Heartbeat interval [30m]: " INTERVAL
    INTERVAL="${INTERVAL:-30m}"

    # Personality
    echo ""
    echo "Available personalities:"
    for d in /app/templates/*/; do
        name=$(basename "$d")
        desc=$(head -1 "$d/SOUL.md" 2>/dev/null | sed 's/^# //')
        echo "  $name — $desc"
    done
    echo ""
    read -p "Personality [philosopher]: " PERSONALITY
    PERSONALITY="${PERSONALITY:-philosopher}"

    # Write config — update Ollama endpoint and model
    cat > "$CONFIG" << JSONEOF
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/$MODEL"
      },
      "heartbeat": {
        "every": "$INTERVAL",
        "target": "none",
        "prompt": "Read HEARTBEAT.md if it exists (workspace context). Follow it strictly. Do not infer or repeat old tasks from prior chats. If nothing needs attention, reply HEARTBEAT_OK."
      },
      "compaction": {
        "mode": "safeguard"
      }
    },
    "list": [
      {
        "id": "main",
        "default": true
      }
    ]
  },
  "models": {
    "mode": "merge",
    "providers": {
      "ollama": {
        "baseUrl": "${OLLAMA_URL}/v1",
        "apiKey": "ollama",
        "api": "ollama",
        "models": [
          {
            "id": "$MODEL",
            "name": "$MODEL",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 32768,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "tools": {
    "profile": "full",
    "allow": ["exec"],
    "exec": {
      "host": "gateway",
      "security": "full"
    }
  },
  "channels": {},
  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "$(head -c 24 /dev/urandom | od -A n -t x1 | tr -d ' \n')"
    }
  }
}
JSONEOF

    # Write .env with Clawbr API key
    cat > "$WORKSPACE/.env" << ENVEOF
AGENTSOCIAL_API_KEY=$API_KEY
CLAWBR_API_KEY=$API_KEY
OLLAMA_API_KEY=ollama
ENVEOF

    # Copy personality template to workspace
    TEMPLATE_DIR="/app/templates/$PERSONALITY"
    if [ -d "$TEMPLATE_DIR" ]; then
        for f in "$TEMPLATE_DIR"/*; do
            fname=$(basename "$f")
            # Replace {{AGENT_NAME}} placeholder
            sed "s/{{AGENT_NAME}}/$AGENT_NAME/g" "$f" > "$WORKSPACE/$fname"
        done
        echo "Loaded personality: $PERSONALITY"
    else
        echo "Warning: personality '$PERSONALITY' not found"
    fi

    # Create memory dir
    mkdir -p "$WORKSPACE/memory"

    echo ""
    echo "Config saved to $CONFIG"
    echo "Workspace at $WORKSPACE"
    echo ""
    echo "Verifying Clawbr API key..."
    VERIFY=$(curl -sf -H "Authorization: Bearer $API_KEY" https://clawbr.org/api/v1/agents/me 2>/dev/null || echo '{"error":"failed"}')
    NAME=$(echo "$VERIFY" | grep -o '"displayName":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$NAME" ]; then
        echo "Authenticated as: $NAME"
    else
        echo "Warning: could not verify API key (agent may not exist yet)"
    fi

    echo ""
    echo "Setup complete! Start with: docker compose up -d"
    echo ""
    exit 0
fi

# Default: run the gateway
echo "Starting OpenClaw gateway (exec-only, Ollama)..."
exec openclaw gateway --port 18789
