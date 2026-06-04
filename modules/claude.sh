#!/usr/bin/env bash
set -euo pipefail

# Pick up custom CA bundle for npm (created by base.sh)
[ -f /etc/ssl/certs/custom-ca-bundle.pem ] && export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/custom-ca-bundle.pem

# Install Claude Code CLI via npm
command -v npm >/dev/null 2>&1 || { echo "Error: claude module requires npm (add node module first)"; exit 1; }
npm install -g @anthropic-ai/claude-code

# Copy settings.json if provided
CLAUDE_CONFIG="${VM_SECRETS}/modules/claude/settings.json"
if [ -f "$CLAUDE_CONFIG" ]; then
  sudo -u "${VM_USER}" bash -c "
    mkdir -p \"\$HOME/.claude\"
    cp '$CLAUDE_CONFIG' \"\$HOME/.claude/settings.json\"
  "
fi

# Install plugins if list provided
PLUGINS_FILE="${VM_SECRETS}/modules/claude/plugins"
if [ -f "$PLUGINS_FILE" ]; then
  while IFS= read -r plugin || [ -n "$plugin" ]; do
    [[ -z "$plugin" || "$plugin" =~ ^# ]] && continue
    echo "Installing Claude plugin: $plugin"
    sudo -u "${VM_USER}" claude plugins install "$plugin" || true
  done < "$PLUGINS_FILE"
fi
