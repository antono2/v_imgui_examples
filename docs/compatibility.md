# Compatibility and package consumers

[`compatibility.json`](../compatibility.json) records the tested upstream V/VC/TCC
commits, V3 frontend profile, docking and standard ImGui releases, transitive
Vulkan/GLFW module releases, Windows native GLFW and CI Vulkan software runtime.
The shared compiler action, compile workflow, release workflow, native release
builder and Windows license collection read these values. `v.mod` remains the
VPM declaration; direct dependency disagreement fails before dependency checkout.
The existing checker validates the recursive module graph, and the compatibility
checker verifies the selected docking/standard release pins after checkout.

Upgrade the manifest and affected `v.mod` declarations together. Run
`python scripts/test_distribution.py` and `python scripts/compatibility.py`.
The required application compilation, four desktop release builds, rendering,
accessibility tests and package consumers validate the upgrade through actual
applications. Keep the advisory current-master checks separate from release pins.

Each package consumer downloads a ZIP onto a separate runner, extracts and
relocates it into a path containing spaces, and launches its menu/argument
launcher from an unrelated working directory. All three examples render and
exit after bounded frame counts; the dashboard wraps its history buffer after
660 frames. A clean user directory and runtime-only PATH prevent developer
configuration from supplying application dependencies. Logs are preserved.

Linux uses a fresh Ubuntu 24.04 container with Python, Xvfb and Vulkan runtime
tools, without V, CMake, a C compiler or system GLFW. Windows uses a separate
hosted VM with build variables removed; operating-system components remain.
CI uses software Vulkan. Physical GPU and manual accessibility validation are
separate release checks.

The **Published desktop package consumers** workflow runs after publication or
manually with a release tag. It downloads each ZIP and `SHA256SUMS.txt`, verifies
the matching checksum, and runs the same consumers. To test a download locally:

```sh
python scripts/test_release_package.py PACKAGE.zip --project imgui --checksums SHA256SUMS.txt
```

On Linux, run inside `xvfb-run -a` when there is no desktop session. Both published
Windows v1.0.1 variants passed this test on the audit machine's physical GPU.

## Read-only diagnostics

Run `python scripts/doctor.py --v PATH_TO_TESTED_V --modules MODULE_DIRECTORY`
to report the selected compiler, build tools and installed dependency versions.
Use `--sdk SDK_DIRECTORY` when VULKAN_SDK is not set, `--runtime` for optional
GPU/driver enumeration, and `--json` for a support report. Each missing or mismatched
prerequisite has a recovery action. Diagnostics do not repair caches or change
the environment. Device enumeration does not validate hardware decoding or
OpenCL interoperability. Python 3.9 or newer is required.

For `doctor.py`, the default `--profile stable` checks the exact compiler commit
stored in `compatibility.json` as `v`; `--profile v3` checks the `v3_v` commit.
Use a compiler built at the selected revision for these diagnostics.

The separate pin resolver uses `--compiler stable` or `--compiler v3`, together
with `--platform linux` or `--platform windows` and `--variant docking` or
`--variant standard`. For example:

```sh
python scripts/compatibility.py --compiler v3 --platform linux --variant standard
python scripts/doctor.py --profile v3 --v PATH_TO_TESTED_V --modules MODULE_DIRECTORY
```
