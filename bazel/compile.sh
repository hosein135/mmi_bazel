#!/usr/bin/env bash
# Compile a writable copy of vendor/mmi. The caller is the Nix toolchain wrapper.
set -euo pipefail

OUT="${1:?bazel output directory}"
ROOT="$(pwd)"
case "$OUT" in
  /*) ;;
  *) OUT="${ROOT}/${OUT}" ;;
esac

for tool in gcc g++ make python3 tclsh ar m4 tar file grep sort; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "mmi compile: ${tool} is not on the Nix toolchain PATH" >&2
    exit 1
  fi
done

if [ ! -d "${ROOT}/vendor/mmi/src/max4.3.16" ]; then
  echo "mmi compile: vendor/mmi sources are not in the execroot (${ROOT})" >&2
  exit 1
fi

# Host CFLAGS must not override the flags in nix/rebuild/build.sh.
unset CFLAGS || true
unset CXXFLAGS || true

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mmi-bazel.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/home" "$WORK/tmp" "$WORK/tree"
export HOME="$WORK/home"
export TMPDIR="$WORK/tmp"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-315532800}"
export TZ="${TZ:-UTC}"
export LC_ALL="${LC_ALL:-C}"
export LANG="${LANG:-C}"

echo "[mmi-bazel] gcc: $(command -v gcc) ($(gcc -dumpversion))"

if ! cp -aL "${ROOT}/vendor/mmi/." "$WORK/tree/"; then
  echo "[mmi-bazel] dereferencing copy failed; copying the tree as-is" >&2
  rm -rf "$WORK/tree"
  mkdir -p "$WORK/tree"
  cp -a "${ROOT}/vendor/mmi/." "$WORK/tree/"
fi
chmod -R u+w "$WORK/tree"

cd "$WORK/tree"
export PATCH_INTPTR="${ROOT}/nix/rebuild/patch-intptr.py"
export PATCH_PCCTS_H="${ROOT}/nix/rebuild/pccts-h"
bash "${ROOT}/nix/rebuild/patch-source.sh" "$PWD"
bash "${ROOT}/nix/rebuild/build.sh"
export LAYOUT_SH="${ROOT}/nix/rebuild/layout.sh"
export SORT_FONT_INDEX_SH="${ROOT}/nix/x11/sort-font-index.sh"
mkdir -p "$OUT"
bash "${ROOT}/nix/rebuild/install.sh" "$PWD" "$OUT"

test -x "$OUT/mmi/bin/max.bin"
test -x "$OUT/mmi/bin/sue.exe"
test -x "$OUT/mmi/bin/nst"
echo "[mmi-bazel] installed $OUT/mmi/bin"
