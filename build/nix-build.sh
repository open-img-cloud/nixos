#!/usr/bin/env bash
# Nix flake build hook called by the build-nix-flake-image reusable workflow.
# Receives: $1 = output dir, $2 = version (e.g. "25.11").
# Must produce: $1/nixos-${version}-x86_64.qcow2
#
# Container expected: ubuntu:24.04 (glibc, so GHA Node24 binaries
# work; nixos/nix:2.21.2 is Alpine/musl and triggers
# 'exec /__e/node24/bin/node: no such file or directory'). Nix is
# installed by this script at startup via the official multi-user
# installer in --no-daemon mode.
#
# Build pipeline:
#   0. Install Nix via curl|sh (single-user mode, no daemon)
#   1. Enable flakes + kvm features in /etc/nix/nix.conf
#   2. Render flake.nix from flake.nix.template (substitute VERSION)
#   3. nix build .#openstack       (calls nixos-generators with our config.nix)
#   4. Copy result/nixos.qcow2 into the workflow's output dir, renamed.

set -euo pipefail

OUT_DIR="${1:?usage: nix-build.sh <output-dir> <version>}"
VERSION="${2:?usage: nix-build.sh <output-dir> <version>}"

CONFIG_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "[nix-build] out_dir=$OUT_DIR version=$VERSION"
echo "[nix-build] config_dir=$CONFIG_DIR"

# --- Install Nix (single-user, no daemon) ---------------------------
# The reusable workflow's prep step gave us curl + xz-utils + sudo +
# ca-certificates already. The Nix installer drops binaries into
# /nix/store and adds a profile script we source.
if ! command -v nix >/dev/null 2>&1; then
  echo "[nix-build] installing Nix..."
  sh <(curl -fsSL https://nixos.org/nix/install) --no-daemon --yes
  # shellcheck source=/dev/null
  . /root/.nix-profile/etc/profile.d/nix.sh
fi
echo "[nix-build] nix version: $(nix --version)"

# --- Enable flakes (and KVM system features for nixos-generators) ---
mkdir -p /etc/nix
{
  echo 'experimental-features = nix-command flakes'
  echo 'system-features = kvm'
} >> /etc/nix/nix.conf

# --- Render flake.nix from template -----------------------------------
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp "$CONFIG_DIR/config.nix" \
   "$CONFIG_DIR/openstack-qcow2-compressed.nix" \
   "$work/"

sed "s/VERSION/${VERSION}/g" "$CONFIG_DIR/flake.nix.template" > "$work/flake.nix"
echo "[nix-build] rendered flake.nix:"
sed -n '1,30p' "$work/flake.nix"

# --- Build the flake's `openstack` package ----------------------------
cd "$work"
echo "[nix-build] running: nix build .#openstack"
nix build .#openstack

# --- Copy the produced qcow2 to the output dir ------------------------
mkdir -p "$OUT_DIR"
final="${OUT_DIR}/nixos-${VERSION}-x86_64.qcow2"

# nixos-generators emits a single .qcow2 in the result/ symlink dir,
# typically named `nixos.qcow2`. Copy out (don't move; result/ is a
# read-only Nix store path) and resolve symlinks to a regular file.
src=$(find -L result -maxdepth 2 -type f -name '*.qcow2' | head -1)
if [[ -z "$src" ]]; then
  echo "::error::no .qcow2 found under result/ — flake build may have produced an unexpected layout"
  ls -la result/ || true
  exit 1
fi

cp -L "$src" "$final"
echo "[nix-build] produced $final"
ls -lh "$final"
