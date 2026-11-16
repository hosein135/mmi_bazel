{
  description = "Toolchain for Micro Magic CAD. Nix prepares the compiler environment. Bazel compiles the sources.";

  nixConfig = {
    extra-experimental-features = "nix-command flakes";
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = false;
      };
      sourceDateEpoch = "315532800";
      bazelPkg = pkgs.bazel_7 or pkgs.bazel;

      # Same compiler and libraries the CAD makefiles were rebuilt with.
      # This derivation stops after writing bin/mmi-env-bash. It does not
      # run nix/rebuild/build.sh.
      toolchainNative = with pkgs; [
        gcc
        binutils
        gnumake
        python3
        file
        gawk
        gnused
        gnugrep
        findutils
        bash
        coreutils
        gnum4
        tcl
        gnutar
        gzip
        diffutils
        patch
        perl
        xorg.mkfontscale
        xorg.mkfontdir
      ];

      toolchainLibs = with pkgs.xorg; [
        libX11
        libXext
        libXt
        libXmu
        libXpm
        libXaw
        libICE
        libSM
        xorgproto
        libXi
        libXrender
      ];

      bazelEnv = pkgs.stdenv.mkDerivation {
        pname = "mmi-bazel-env";
        version = "040526";
        # Present so stdenv accepts the derivation. dontUnpack keeps it unused.
        src = ./nix/dump-env.py;
        dontUnpack = true;
        dontConfigure = true;
        dontBuild = true;
        dontFixup = true;
        nativeBuildInputs = toolchainNative;
        buildInputs = toolchainLibs;
        hardeningDisable = [
          "format"
          "fortify"
          "fortify3"
          "stackprotector"
          "pic"
          "strictoverflow"
        ];
        NIX_CFLAGS_COMPILE = "-std=gnu89 -fcommon -fno-strict-aliasing -frandom-seed=mmi-cad-040526 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -fpermissive -Wno-error -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-pointer-to-int-cast -Wno-int-to-pointer-cast -Wno-return-type -Wno-unused -Wno-builtin-declaration-mismatch -Wno-endif-labels -include float.h -DCLK_TCK=100 -DUSE_SYSTEM_MALLOC";
        SOURCE_DATE_EPOCH = sourceDateEpoch;
        TZ = "UTC";
        LC_ALL = "C";
        LANG = "C";
        installPhase = ''
          mkdir -p "$out/bin"
          python3 ${./nix/dump-env.py} "$out/bin/mmi-env-bash" "${pkgs.bash}/bin/bash"
          chmod 755 "$out/bin/mmi-env-bash"
          bash -n "$out/bin/mmi-env-bash"
        '';
        meta = {
          description = "Nix toolchain wrapper used by Bazel to compile Micro Magic CAD";
          platforms = [ "x86_64-linux" ];
        };
      };
    in
    {
      packages.${system} = {
        default = bazelEnv;
        bazel-env = bazelEnv;
      };

      checks.${system}.bazel-env = pkgs.runCommand "check-mmi-bazel-env" { } ''
        script=${bazelEnv}/bin/mmi-env-bash
        grep -q '/nix/store/' "$script"
        grep -q 'libX11' "$script"
        grep -q 'NIX_CFLAGS_COMPILE' "$script"
        touch "$out"
      '';

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          bazelPkg
          pkgs.nix
          pkgs.git
          pkgs.coreutils
          pkgs.bash
        ];
        shellHook = ''
          echo "Nix shell is ready. Bazel compiles the CAD tools:"
          echo "  bazel build //:mmi-vendor"
          echo "Toolchain only: nix build .#bazel-env"
        '';
      };
    };
}
