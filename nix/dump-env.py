#!/usr/bin/env python3
"""Write a bash wrapper that reproduces this Nix builder's toolchain.

The wrapper is what Bazel executes. It does not compile the CAD tools.
"""
import os
import shlex
import shutil
import sys

EXACT = {
    "CC",
    "CXX",
    "CPP",
    "AS",
    "LD",
    "NM",
    "AR",
    "RANLIB",
    "STRIP",
    "OBJCOPY",
    "OBJDUMP",
    "READELF",
    "SIZE",
    "STRINGS",
    "CONFIG_SHELL",
    "CPATH",
    "LIBRARY_PATH",
    "C_INCLUDE_PATH",
    "CPLUS_INCLUDE_PATH",
    "PKG_CONFIG_PATH",
    "PKG_CONFIG",
    "SOURCE_DATE_EPOCH",
    "TZ",
    "LC_ALL",
    "LANG",
    "NIX_CFLAGS_COMPILE",
    "NIX_CFLAGS_LINK",
    "NIX_LDFLAGS",
    "NIX_LDFLAGS_BEFORE",
    "NIX_LDFLAGS_AFTER",
    "NIX_HARDENING_ENABLE",
    "NIX_CC",
    "NIX_BINTOOLS",
    "NIX_STORE",
}

REQUIRED = [
    "gcc",
    "g++",
    "cpp",
    "make",
    "python3",
    "tclsh",
    "ar",
    "m4",
    "tar",
    "file",
    "bash",
    "grep",
    "sort",
]


def keep(name):
    if name in EXACT:
        return True
    if name.startswith("NIX_CC_WRAPPER_") or name.startswith("NIX_BINTOOLS_WRAPPER_"):
        return True
    return False


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: dump-env.py DEST BASH")
    dest, bash = sys.argv[1], sys.argv[2]
    if not bash.startswith("/nix/store/"):
        raise SystemExit("bash is not in the Nix store: " + bash)

    for tool in REQUIRED:
        found = shutil.which(tool)
        if not found:
            raise SystemExit("mmi bazel env: missing " + tool)
        real = os.path.realpath(found)
        if not real.startswith("/nix/store/"):
            raise SystemExit("mmi bazel env: %s is not in the Nix store (%s)" % (tool, real))

    ldflags = os.environ.get("NIX_LDFLAGS", "")
    cflags = os.environ.get("NIX_CFLAGS_COMPILE", "")
    if "libX11" not in ldflags and "libX11" not in cflags and "libX11" not in os.environ.get("LIBRARY_PATH", ""):
        raise SystemExit("mmi bazel env: X11 flags were not captured in NIX_LDFLAGS")

    path_parts = []
    seen = set()
    for part in os.environ.get("PATH", "").split(":"):
        if not part.startswith("/nix/store/") or not os.path.isdir(part):
            continue
        if part in seen:
            continue
        seen.add(part)
        path_parts.append(part)
    if not path_parts:
        raise SystemExit("mmi bazel env: no /nix/store PATH entries")

    lines = [
        "#!" + bash,
        "set -eu",
        "export PATH=" + shlex.quote(":".join(path_parts)),
    ]
    for name in sorted(os.environ):
        if not keep(name):
            continue
        value = os.environ[name]
        if value == "" or "\n" in value or "\0" in value:
            continue
        lines.append("export %s=%s" % (name, shlex.quote(value)))
    lines.append("exec " + shlex.quote(bash) + ' "$@"')
    lines.append("")
    with open(dest, "w", newline="\n") as handle:
        handle.write("\n".join(lines))
    os.chmod(dest, 0o755)


if __name__ == "__main__":
    main()
