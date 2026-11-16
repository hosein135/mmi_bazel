#!/usr/bin/env bash
# Compile the CAD tools. After a successful build, put each tool that is
# not already on PATH into ~/.local/bin.
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  echo "run.sh: run ./run.sh instead of sourcing it." >&2
  return 1
fi

set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
cd "$ROOT"

echo "Compiling CAD tools (Nix toolchain, Bazel build)"
bash ./build.sh

bindir="$ROOT/bazel-bin/mmi-vendor/mmi/bin"
tools_root="$ROOT/bazel-bin/mmi-vendor/mmi"
importer="$ROOT/pdk/importer/importer"

if [ ! -d "$bindir" ]; then
  echo "run.sh: ${bindir} does not exist after the build." >&2
  exit 1
fi
if [ -z "${HOME:-}" ]; then
  echo "run.sh: HOME is not set, so the tools cannot be added to PATH." >&2
  exit 1
fi

dest="$HOME/.local/bin"
mkdir -p "$dest"

wrapper_tmp=""
cleanup() {
  if [ -n "${wrapper_tmp}" ]; then
    rm -f "${wrapper_tmp}"
  fi
}
trap cleanup EXIT

sh_quote() {
  local s=$1
  s=${s//\'/\'\\\'\'}
  printf "'%s'" "$s"
}

is_ours() {
  local f=$1 first second
  [ -f "$f" ] || return 1
  {
    IFS= read -r first || return 1
    IFS= read -r second || return 1
  } < "$f"
  [ "$first" = "#!/bin/sh" ] && [ "$second" = "# mmi-bazel-tool" ]
}

write_wrapper() {
  local src=$1 wrapper=$2 kind=$3
  wrapper_tmp=$(mktemp "${dest}/.mmi-tool.XXXXXX")
  {
    printf '%s\n' '#!/bin/sh' '# mmi-bazel-tool'
    if [ "$kind" = "cad" ]; then
      printf 'export MMI_TOOLS=%s\n' "$(sh_quote "$tools_root")"
      printf '%s\n' 'export MN_BIN_DIR="${MN_BIN_DIR:-bin.linux}"'
      if [ -d "$tools_root/lib/tcl8.0" ]; then
        printf 'export TCL_LIBRARY=%s\n' "$(sh_quote "$tools_root/lib/tcl8.0")"
      fi
      if [ -d "$tools_root/lib/tk8.0" ]; then
        printf 'export TK_LIBRARY=%s\n' "$(sh_quote "$tools_root/lib/tk8.0")"
      fi
      if [ -d "$tools_root/app-defaults" ]; then
        printf 'export XAPPLRESDIR=%s\n' "$(sh_quote "$tools_root/app-defaults")"
      fi
      if [ -d "$tools_root/max/fonts" ]; then
        printf 'export MMI_MAX_FONTS_DIR=%s\n' "$(sh_quote "$tools_root/max/fonts")"
      fi
      printf 'exec %s "$@"\n' "$(sh_quote "$src")"
    else
      printf 'exec sh %s "$@"\n' "$(sh_quote "$src")"
    fi
  } > "$wrapper_tmp"
  chmod 755 "$wrapper_tmp"
  mv -f "$wrapper_tmp" "$wrapper"
  wrapper_tmp=""
}

added=()
skipped=()
installed_ours=0

consider() {
  local src=$1 kind=$2 name existing wrapper was_present
  name=$(basename "$src")
  wrapper="${dest}/${name}"
  existing=$(type -P "$name" 2>/dev/null || true)
  if [ -n "$existing" ] && ! is_ours "$existing"; then
    skipped+=("$name")
    return 0
  fi
  if [ -e "$wrapper" ] && ! is_ours "$wrapper"; then
    echo "run.sh: ${name} is not on PATH, and ${wrapper} already exists. Left it alone." >&2
    return 0
  fi
  was_present=0
  if [ -n "$existing" ] || is_ours "$wrapper"; then
    was_present=1
  fi
  write_wrapper "$src" "$wrapper" "$kind"
  installed_ours=1
  if [ "$was_present" -eq 0 ]; then
    added+=("$name")
  fi
}

found=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -x "${bindir}/${name}" ] || continue
  consider "${bindir}/${name}" cad
  found=1
done < <(LC_ALL=C find "$bindir" -maxdepth 1 \( -type f -o -type l \) -printf '%f\n' | LC_ALL=C sort)

if [ "$found" -eq 0 ]; then
  echo "run.sh: no executables in ${bindir}." >&2
  exit 1
fi

if [ -f "$importer" ]; then
  consider "$importer" importer
fi

on_path=0
case ":${PATH}:" in
  *":${dest}:"*) on_path=1 ;;
esac

user_rc() {
  case "${SHELL:-}" in
    */zsh) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;;
    *) printf '%s\n' "$HOME/.bashrc" ;;
  esac
}

need_new_shell=0
if [ "$installed_ours" -eq 1 ] && [ "$on_path" -eq 0 ]; then
  rc=$(user_rc)
  mkdir -p "$(dirname "$rc")"
  touch "$rc"
  if ! grep -qF '# >>> mmi-bazel path >>>' "$rc"; then
    printf '\n' >> "$rc"
    cat >> "$rc" << 'EOF'
# >>> mmi-bazel path >>>
case ":${PATH}:" in
  *":${HOME}/.local/bin:"*) ;;
  *) PATH="${HOME}/.local/bin:${PATH}" ;;
esac
export PATH
# <<< mmi-bazel path <<<
EOF
  fi
  need_new_shell=1
fi

if [ ${#added[@]} -gt 0 ]; then
  echo "Added to PATH: ${added[*]}"
fi
if [ ${#skipped[@]} -gt 0 ]; then
  echo "Already on PATH: ${skipped[*]}"
fi
if [ ${#added[@]} -eq 0 ] && [ ${#skipped[@]} -eq 0 ] && [ "$on_path" -eq 1 ]; then
  echo "CAD tools are already on PATH."
fi
if [ "$need_new_shell" -eq 1 ]; then
  echo "${dest} was not on PATH. New shells pick it up from ${rc}."
  echo "Open a new terminal, or run: source ${rc}"
elif [ "$on_path" -eq 1 ] && [ ${#added[@]} -gt 0 ]; then
  echo "You can run them in this terminal."
fi
