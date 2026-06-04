#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Preflight ---

command -v limactl >/dev/null 2>&1 || { echo "Error: limactl not found. Install with: brew install lima"; exit 1; }
command -v yq >/dev/null 2>&1 || { echo "Error: yq not found. Install with: brew install yq"; exit 1; }

# --- Arguments ---

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
VM_NAME="$PROJECT_NAME"

# Validate project name is safe for use in VM names and paths
[[ "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || {
  echo "Error: project name must contain only letters, digits, hyphens, or underscores"
  exit 1
}

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

# --- Create VM with project mount ---

TEMP_YAML="$(mktemp)"
trap 'rm -f "$TEMP_YAML"' EXIT

cp "$REPO_DIR/base.yaml" "$TEMP_YAML"

# Derive a valid Linux username from the host username following Lima's rules
VM_USER="$(id -un)"
VM_USER="$(printf '%s' "$VM_USER" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '_')"
[[ "$VM_USER" =~ ^[a-z_] ]] || VM_USER="_${VM_USER}"
VM_USER="${VM_USER:0:32}"
[[ -n "$VM_USER" ]] || VM_USER="lima"

LIMA_INFO="$(limactl info)"
DEFAULT_HOME="$(printf '%s' "$LIMA_INFO" | yq -r '.defaultTemplate.user.home')"
DEFAULT_USER="$(printf '%s' "$LIMA_INFO" | yq -r '.defaultTemplate.user.name')"
[[ -n "$DEFAULT_HOME" && "$DEFAULT_HOME" != "null" ]] || { echo "Error: could not resolve guest home directory from limactl info"; exit 1; }
GUEST_HOME="${DEFAULT_HOME/$DEFAULT_USER/$VM_USER}"
MOUNT_POINT="${GUEST_HOME}/${PROJECT_NAME}"

yq -i ".user.name = \"$VM_USER\" | .user.home = \"$GUEST_HOME\"" "$TEMP_YAML"

yq -i ".mounts += [{
  \"location\": \"$HOST_PROJECT_PATH\",
  \"mountPoint\": \"$MOUNT_POINT\",
  \"writable\": true
}]" "$TEMP_YAML"

echo "Creating VM: $VM_NAME"
limactl create --name="$VM_NAME" --tty=false "$TEMP_YAML"

echo "Starting VM: $VM_NAME"
limactl start "$VM_NAME"

# --- Detect VM user ---

VM_USER="$(limactl shell "$VM_NAME" whoami)"
[[ -n "$VM_USER" ]] || { echo "Error: could not detect VM user"; exit 1; }

# --- Run modules via stdin ---

# Always run base
echo "Running module: base"
limactl shell "$VM_NAME" sudo bash -c '
  export VM_USER="$1" VM_PROJECT="$2" VM_SECRETS="$3"
  export DEBIAN_FRONTEND=noninteractive
  bash -euo pipefail -s
' -- "$VM_USER" "$PROJECT_NAME" '/mnt/host/ai-dev-vm' < "$REPO_DIR/modules/base.sh"

# Run modules from config in order
while IFS= read -r mod; do
  [[ -z "$mod" || "$mod" == "null" ]] && continue
  MODULE_FILE="$REPO_DIR/modules/${mod}.sh"
  if [ ! -f "$MODULE_FILE" ]; then
    echo "Warning: module '$mod' not found at $MODULE_FILE, skipping"
    continue
  fi
  echo "Running module: $mod"
  limactl shell "$VM_NAME" sudo bash -c '
    export VM_USER="$1" VM_PROJECT="$2" VM_SECRETS="$3"
    export DEBIAN_FRONTEND=noninteractive
    bash -euo pipefail -s
  ' -- "$VM_USER" "$PROJECT_NAME" '/mnt/host/ai-dev-vm' < "$MODULE_FILE"
done <<< "$(yq -r '.modules[]' "$CONFIG_FILE" 2>/dev/null || true)"

echo "Restarting VM to apply group changes: $VM_NAME"
limactl restart "$VM_NAME"

echo
echo "VM ready: $VM_NAME"
echo
echo "Connect:"
echo "  limactl shell $VM_NAME"
echo "  ssh lima-$VM_NAME"
echo
echo "VS Code:"
echo "  Remote-SSH -> lima-$VM_NAME"
