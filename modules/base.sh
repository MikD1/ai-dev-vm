#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  wget \
  git \
  git-lfs \
  jq \
  ripgrep \
  fd-find \
  build-essential \
  pkg-config \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common

# Ubuntu names fd as fdfind — create symlink
ln -sf "$(command -v fdfind)" /usr/local/bin/fd || true

git lfs install --system || true

# Copy gitconfig from host, stripping credential helpers
if [ -f "${VM_SECRETS}/.gitconfig" ]; then
  sudo -u "${VM_USER}" env VM_SECRETS="${VM_SECRETS}" bash -c '
    grep -v -i "credential\." "${VM_SECRETS}/.gitconfig" > "$HOME/.gitconfig" || true
  '
fi
