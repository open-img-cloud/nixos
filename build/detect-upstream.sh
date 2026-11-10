#!/usr/bin/env bash
# Prints the latest NixOS stable release version on stdout (e.g. "26.05").
#
# NixOS uses a YY.MM release scheme on a 6-month cadence (May / November).
#
# Primary signal: release tags on github.com/NixOS/nixpkgs (e.g. "26.05").
# A tag is only pushed once the release is official, whereas the
# `nixos-X.Y` branch exists from branch-off (beta) onwards, so tags never
# report a pre-release. The `git/matching-refs` endpoint returns every
# matching ref in one response (no pagination), unlike `/branches`, which
# only returns the first 100 branches alphabetically and missed new
# releases.
#
# Fallback: probe channels.nixos.org for the next YY.05 / YY.11 channels
# after the version pinned in VERSION. Note that a channel may already
# exist during beta; the fallback is only used if the GitHub API fails.
#
# Runs in the upstream-watch reusable workflow (no KVM needed): keep
# it portable bash + curl + grep + sort only.

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

latest=$(curl -fsL \
  -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/repos/NixOS/nixpkgs/git/matching-refs/tags/' 2>/dev/null \
  | grep -oE '"ref":[[:space:]]*"refs/tags/[0-9]{2}\.(05|11)"' \
  | grep -oE '[0-9]{2}\.(05|11)' \
  | sort -uV | tail -n1 \
  || true)

if [[ -z "$latest" ]]; then
  echo "::warning::GitHub API unavailable, falling back to channels.nixos.org probing" >&2
  current=$(tr -d '[:space:]' < "$script_dir/../VERSION" 2>/dev/null || true)
  if [[ ! "$current" =~ ^([0-9]{2})\.(05|11)$ ]]; then
    echo "::error::could not list nixpkgs tags and VERSION ('$current') is not YY.05/YY.11" >&2
    exit 1
  fi
  latest=$current
  yy=$((10#${BASH_REMATCH[1]})); mm=${BASH_REMATCH[2]}
  # Walk forward release by release until a channel is missing.
  while :; do
    if [[ $mm == 05 ]]; then mm=11; else mm=05; yy=$((yy + 1)); fi
    candidate=$(printf '%02d.%s' "$yy" "$mm")
    code=$(curl -s -o /dev/null -w '%{http_code}' -I "https://channels.nixos.org/nixos-$candidate" || true)
    [[ $code == 200 || $code == 301 || $code == 302 ]] || break
    latest=$candidate
  done
fi

if [[ -z "${latest:-}" ]]; then
  echo "::error::no NixOS release found on github.com/NixOS/nixpkgs" >&2
  exit 1
fi

printf '%s\n' "$latest"
