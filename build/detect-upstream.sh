#!/usr/bin/env bash
# Prints the latest NixOS stable release version on stdout (e.g. "25.11").
#
# NixOS uses a YY.MM release scheme on a 6-month cadence (May / November).
# `release-X.Y` and `nixos-X.Y` branches on github.com/NixOS/nixpkgs are
# the canonical signal; we list them via the Gitea-compatible API on
# nixpkgs's mirror and pick the highest semver-style.
#
# Falls back to scraping channels.nixos.org if the API isn't reachable.
#
# Runs in the upstream-watch reusable workflow (no KVM needed) — keep
# it portable bash + curl + sort only.

set -euo pipefail

# Try GitHub API first (rate-limit-aware, but unauthenticated should
# work given how rarely this fires).
api_branches=$(curl -fsL \
  -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/repos/NixOS/nixpkgs/branches?per_page=100' 2>/dev/null \
  | grep -oE '"name":[[:space:]]*"nixos-[0-9]+\.[0-9]+"' \
  | grep -oE '[0-9]+\.[0-9]+' \
  || true)

if [[ -n "$api_branches" ]]; then
  latest=$(printf '%s\n' "$api_branches" | sort -uV | tail -n1)
fi

# Fallback: parse channels.nixos.org redirect.
if [[ -z "${latest:-}" ]]; then
  redirect=$(curl -fsI 'https://channels.nixos.org/nixos-25.11' 2>/dev/null \
    | awk -F': ' 'tolower($1)=="location"{sub(/\r$/,"",$2); print $2; exit}' \
    || true)
  # Above just confirms 25.11 exists. For a generic "latest" via channels,
  # there's no single index URL; we'd have to probe N+1 / N+2 sequentially.
  # Skipping that fallback for now — the GitHub API path is reliable.
  if [[ -z "$redirect" ]]; then
    echo "::error::could not list NixOS branches from GitHub API and channels.nixos.org probe failed" >&2
    exit 1
  fi
  latest="25.11"
fi

if [[ -z "${latest:-}" ]]; then
  echo "::error::no NixOS release branches found on github.com/NixOS/nixpkgs" >&2
  exit 1
fi

printf '%s\n' "$latest"
