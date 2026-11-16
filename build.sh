#!/usr/bin/env bash
# Nix enters a shell that contains Bazel, then Bazel compiles the CAD tools.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v nix >/dev/null 2>&1; then
  echo "Install Nix on x86_64 Linux, then run: bash build.sh" >&2
  exit 1
fi

exec nix --extra-experimental-features "nix-command flakes" develop --accept-flake-config --command bazel build //:mmi-vendor
