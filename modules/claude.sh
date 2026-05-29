#!/usr/bin/env bash
set -euo pipefail

# Requires node module to have run first
command -v npm >/dev/null 2>&1 || { echo "Error: claude module requires the node module"; exit 1; }

# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code

# Copy settings.json if provided
CLAUDE_CONFIG="${VM_SECRETS}/modules/claude/settings.json"
if [ -f "$CLAUDE_CONFIG" ]; then
  sudo -u "${VM_USER}" bash -c "
    mkdir -p \"\$HOME/.claude\"
    cp '$CLAUDE_CONFIG' \"\$HOME/.claude/settings.json\"
  "
fi
