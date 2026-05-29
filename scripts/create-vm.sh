#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <project-name> [host-project-path]"
  echo
  echo "  host-project-path defaults to ~/Projects/<project-name>"
  echo
  echo "Examples:"
  echo "  $0 my-api"
  echo "  $0 my-api ~/Work/my-api"
  exit 1
fi

PROJECT_NAME="$1"
HOST_PROJECT_PATH="${2:-$HOME/Projects/$PROJECT_NAME}"
VM_NAME="dev-${PROJECT_NAME}"

# --- Validate ---

if [ ! -d "$HOST_PROJECT_PATH" ]; then
  echo "Error: project directory not found: $HOST_PROJECT_PATH"
  echo "Clone the repository on the host first."
  exit 1
fi

HOST_PROJECT_PATH="$(cd "$HOST_PROJECT_PATH" && pwd)"

CONFIG_FILE="${HOST_PROJECT_PATH}/.ai-dev-vm.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: .ai-dev-vm.yaml not found in $HOST_PROJECT_PATH"
  echo "Create it with a list of modules, e.g.:"
  echo "  modules:"
  echo "    - node"
  echo "    - docker"
  echo "    - claude"
  exit 1
fi

if limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "$VM_NAME"; then
  echo "Error: VM '$VM_NAME' already exists."
  echo "Delete it first: ./scripts/delete-vm.sh $PROJECT_NAME"
  exit 1
fi

# --- Propagate proxy from host secrets if available ---

if [ -f "$HOME/.config/ai-dev/secrets.env" ]; then
  eval "$(grep -Ei '^(HTTPS?_PROXY|NO_PROXY)=' "$HOME/.config/ai-dev/secrets.env")" || true
  export HTTP_PROXY HTTPS_PROXY NO_PROXY 2>/dev/null || true
fi

# --- Create VM with project mount ---

TEMP_YAML="$(mktemp)"
trap 'rm -f "$TEMP_YAML"' EXIT

cp "$REPO_DIR/base.yaml" "$TEMP_YAML"

# Add writable project mount
yq -i ".mounts += [{
  \"location\": \"$HOST_PROJECT_PATH\",
  \"mountPoint\": \"/home/\(.ssh.localUser // \"user\").linux/$PROJECT_NAME\",
  \"writable\": true
}]" "$TEMP_YAML"

echo "Creating VM: $VM_NAME"
limactl create --name="$VM_NAME" --tty=false "$TEMP_YAML"

echo "Starting VM: $VM_NAME"
limactl start "$VM_NAME"

# --- Detect VM user ---

VM_USER="$(limactl shell "$VM_NAME" whoami)"

# --- Run modules via stdin (no need to copy files into VM) ---

# Always run base
echo "Running module: base"
limactl shell --root "$VM_NAME" bash -c "
  export VM_USER='$VM_USER'
  export VM_PROJECT='$PROJECT_NAME'
  export VM_SECRETS='/mnt/host/ai-dev'
  export DEBIAN_FRONTEND=noninteractive
  bash -euo pipefail
" < "$REPO_DIR/modules/base.sh"

# Run modules from config in order
MODULES="$(yq -r '.modules[]' "$CONFIG_FILE" 2>/dev/null || true)"

for mod in $MODULES; do
  MODULE_FILE="$REPO_DIR/modules/${mod}.sh"
  if [ ! -f "$MODULE_FILE" ]; then
    echo "Warning: module '$mod' not found at $MODULE_FILE, skipping"
    continue
  fi
  echo "Running module: $mod"
  limactl shell --root "$VM_NAME" bash -c "
    export VM_USER='$VM_USER'
    export VM_PROJECT='$PROJECT_NAME'
    export VM_SECRETS='/mnt/host/ai-dev'
    export DEBIAN_FRONTEND=noninteractive
    bash -euo pipefail
  " < "$MODULE_FILE"
done

echo
echo "VM ready: $VM_NAME"
echo
echo "Connect:"
echo "  limactl shell $VM_NAME"
echo "  ssh lima-$VM_NAME"
echo
echo "VS Code:"
echo "  Remote-SSH -> lima-$VM_NAME"
