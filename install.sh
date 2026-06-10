#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/ai-dev-vm"
BIN_DIR="$HOME/.local/bin"
VM_LINK="$BIN_DIR/vm"

# 1. Check prerequisites (check & instruct; never install packages).
missing=()
command -v brew >/dev/null 2>&1 || missing+=("brew")
command -v limactl >/dev/null 2>&1 || missing+=("lima")
command -v yq >/dev/null 2>&1 || missing+=("yq")
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing prerequisites: ${missing[*]}"
  if printf '%s\n' "${missing[@]}" | grep -qx "brew"; then
    echo "Install Homebrew first: https://brew.sh"
  fi
  brew_pkgs=()
  for p in "${missing[@]}"; do [[ "$p" != "brew" ]] && brew_pkgs+=("$p"); done
  if [ "${#brew_pkgs[@]}" -gt 0 ]; then
    echo "Then install the missing tools:"
    echo "  brew install ${brew_pkgs[*]}"
  fi
  exit 1
fi

# 2. Config directory.
if [ ! -d "$CONFIG_DIR" ]; then
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  echo "Created $CONFIG_DIR"
fi

# 3. Copy host gitconfig only if present and not already copied.
if [ -f "$HOME/.gitconfig" ] && [ ! -f "$CONFIG_DIR/.gitconfig" ]; then
  cp "$HOME/.gitconfig" "$CONFIG_DIR/.gitconfig"
  echo "Copied ~/.gitconfig -> $CONFIG_DIR/.gitconfig"
fi

# 4. Symlink the vm launcher onto PATH.
[[ -f "$REPO_DIR/bin/vm" ]] || { echo "Error: $REPO_DIR/bin/vm not found"; exit 1; }
mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/bin/vm" "$VM_LINK"
echo "Linked $VM_LINK -> $REPO_DIR/bin/vm"

# 5. PATH check.
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *)
    echo
    echo "$BIN_DIR is not on your PATH. Add this to your shell rc:"
    printf "  export PATH=\"%s:\$PATH\"\n" "$BIN_DIR"
    ;;
esac

# 6. Summary.
echo
echo "Done. You're ready — try: vm init"
