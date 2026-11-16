#!/usr/bin/env bash
# This tree compiles with Bazel. The Nix shell only provides Bazel and the toolchain.
set -euo pipefail
cd "$(dirname "$0")"
echo "Compiling CAD tools (Nix toolchain, Bazel build)"
exec bash ./build.sh
