"""Fetch the Nix toolchain that Bazel uses to compile the CAD sources.

This rule runs `nix build .#bazel-env`. That derivation installs gcc, make,
Python, Tcl, GNU tar, and the X11 libraries, then writes a wrapper script
with those paths and the compiler flags. It does not compile MAX, SUE, or NST.
"""

def _mmi_nix_env_impl(repository_ctx):
    for label in [repository_ctx.attr.flake, repository_ctx.attr.lock, repository_ctx.attr.dump]:
        repository_ctx.path(label)

    repository_ctx.file(
        "BUILD.bazel",
        """exports_files(
    ["mmi-env-bash"],
    visibility = ["//visibility:public"],
)
""",
    )

    if repository_ctx.os.name != "linux":
        repository_ctx.file(
            "mmi-env-bash",
            """#!/bin/sh
echo "The CAD toolchain is built by Nix on x86_64 Linux." >&2
exit 1
""",
            executable = True,
        )
        return

    nix = repository_ctx.which("nix")
    if not nix:
        fail("nix is not on PATH. Install Nix, then run: bash build.sh")

    repository_ctx.report_progress("Nix is preparing the CAD toolchain")
    installable = "path:%s#bazel-env" % repository_ctx.workspace_root
    result = repository_ctx.execute(
        [
            nix,
            "--extra-experimental-features",
            "nix-command flakes",
            "build",
            "--accept-flake-config",
            "--no-link",
            "--print-out-paths",
            installable,
        ],
        timeout = 7200,
        quiet = False,
        working_directory = str(repository_ctx.workspace_root),
    )
    if result.return_code != 0:
        detail = (result.stderr or "") + "\n" + (result.stdout or "")
        fail("nix build .#bazel-env failed:\n" + detail[-12000:])

    store = ""
    for line in (result.stdout or "").splitlines():
        line = line.strip()
        if line.startswith("/nix/store/"):
            store = line
    if not store:
        fail("nix build .#bazel-env did not print a store path:\n" + (result.stdout or ""))

    script = store + "/bin/mmi-env-bash"
    repository_ctx.report_progress("Copying the Nix toolchain wrapper")
    # Read through Nix so the copy does not depend on host cp or on Bazel
    # allowing template() to open a store path.
    read = repository_ctx.execute(
        [
            nix,
            "--extra-experimental-features",
            "nix-command",
            "eval",
            "--raw",
            "--impure",
            "--expr",
            "builtins.readFile " + script,
        ],
        timeout = 180,
    )
    if read.return_code != 0:
        fail("failed to read " + script + ":\n" + (read.stderr or ""))
    content = read.stdout or ""
    if not content.startswith("#!"):
        fail("toolchain wrapper is empty or not a script: " + script)
    repository_ctx.file("mmi-env-bash", content, executable = True)

mmi_nix_env = repository_rule(
    implementation = _mmi_nix_env_impl,
    configure = True,
    attrs = {
        "flake": attr.label(mandatory = True, allow_single_file = ["flake.nix"]),
        "lock": attr.label(mandatory = True, allow_single_file = ["flake.lock"]),
        "dump": attr.label(mandatory = True, allow_single_file = True),
    },
)
