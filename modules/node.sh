#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Pick up custom CA bundle for corepack/npm (created by base.sh)
[ -f /etc/ssl/certs/custom-ca-bundle.pem ] && export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/custom-ca-bundle.pem

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y nodejs
fi

corepack enable || true
corepack install --global pnpm@latest || true
corepack install --global yarn@stable || true
