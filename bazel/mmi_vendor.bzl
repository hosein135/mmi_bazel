"""Compile the Micro Magic CAD tree with the Nix toolchain.

Nix has already captured gcc, make, headers, libraries, and flags in
`@mmi_nix_env//:mmi-env-bash`. This rule runs that wrapper over the existing
patch, make, and install scripts and returns the installed tree.
"""

def _mmi_vendor_impl(ctx):
    out = ctx.actions.declare_directory(ctx.label.name)
    ctx.actions.run(
        executable = ctx.file.env_bash,
        arguments = [ctx.file.driver.path, out.path],
        inputs = depset(ctx.files.srcs + [ctx.file.driver, ctx.file.env_bash]),
        tools = [ctx.file.env_bash],
        outputs = [out],
        execution_requirements = {
            "local": "1",
            "no-sandbox": "1",
            "no-remote": "1",
        },
        mnemonic = "MmiCompile",
        progress_message = "Compiling Micro Magic CAD with the Nix toolchain",
        use_default_shell_env = False,
    )
    return [DefaultInfo(files = depset([out]))]

mmi_vendor = rule(
    implementation = _mmi_vendor_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True, mandatory = True),
        "driver": attr.label(allow_single_file = True, mandatory = True),
        "env_bash": attr.label(allow_single_file = True, mandatory = True),
    },
)
