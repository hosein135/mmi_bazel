# Micro Magic CAD (Nix toolchain, Bazel build)

Nix prepares the compiler environment. Bazel compiles the CAD sources.

The toolchain derivation `.#bazel-env` installs gcc, GNU make, Python, Tcl, tar, m4, and the X11 headers and libraries, then writes those paths and the compiler flags into `bin/mmi-env-bash`. It does not compile MAX, SUE, or NST.

`bazel build //:mmi-vendor` runs that wrapper. The wrapper's shell executes `bazel/compile.sh`, which patches `vendor/mmi`, runs the existing makefiles, and installs the ELF 64-bit tools.

## Requirements

- x86_64 Linux (bare metal, a VM, or WSL2)
- Nix with flakes (Nix 2.28 or newer is fine)
- A few GiB free on the first build, so Nix can fetch nixpkgs and Bazel can compile the tree

Bazel 7 comes from the Nix shell. Windows is not a compile target.

## Build

```bash
bash build.sh
```

That is:

```bash
nix develop --command bazel build //:mmi-vendor
```

The first Bazel invocation runs `nix build .#bazel-env` to materialize the toolchain, then compiles. Later builds reuse the toolchain and recompile only when sources or the toolchain description change.

Installed tools:

```text
bazel-bin/mmi-vendor/mmi/bin/
```

`max.bin`, `sue.exe`, `nst`, `sue_tee`, `ext2spice`, `ext2sim`, `gemini`, `irsim`, `anXhelper`, and `edif2sue` are in that directory.

Toolchain only, without compiling CAD:

```bash
nix build .#bazel-env
# or, once Nix and Bazel are both on PATH:
bazel build //:bazel-env
```

nixpkgs is NixOS 25.05, pinned by `flake.lock`.

The previous all-in-Nix FHS runner is described in `README.nix-fhs.md`. This tree's flake no longer builds the CAD binaries itself.
