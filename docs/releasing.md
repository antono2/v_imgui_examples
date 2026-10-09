# Creating release assets

Run the **Portable release packages** workflow on the intended examples commit.
It builds both pinned ImGui variants, bundles all non-OS desktop libraries,
audits runtime dependencies, renders the Linux bundles and builds unsigned
Android inputs for three ABIs. Download the artifacts from that exact run.
Retain the run URL and source commits in release notes. Do not publish CI debug
APKs as release updates: their signing keys are temporary.

The release helpers are V programs with shared build, packaging, license and
ZIP code in `scripts/release_tools/`. From prepared dependencies, run
`./scripts/build_release.v docking` (or `standard`) on Linux. On Windows
first load `. scripts/setup_windows_build.ps1` in PowerShell to select Visual
Studio, then use `v -prod run scripts/build_release.v docking`. For the other V
helpers below, Windows also uses `v run` (or `v -prod run`) before the script path.
To package existing binaries, use `./scripts/package_release.v
binary-dir imgui-dir output-dir docking`. License collection uses
`./scripts/collect_licenses.v imgui-dir output-dir`, with `android` as its
last argument for mobile notices.

Desktop ZIPs are ready to promote after reviewing the checks. Android APKs are
signed outside CI with the persistent private release key:

```sh
./scripts/sign_android_release.v \
  --input /path/to/android-release-input-armeabi-v7a \
  --input /path/to/android-release-input-arm64-v8a \
  --input /path/to/android-release-input-x86_64 \
  --output /path/to/release-assets \
  --build-tools "$ANDROID_SDK_ROOT/build-tools/36.0.0" \
  --keystore /private/path/release.keystore \
  --password-file /private/path/password.txt
```

The script rejects mismatched common APK content, combines the ABI libraries,
embeds license notices, aligns the APKs, signs them and verifies each signature.
Keep the key and password private and backed up outside the repository. Never
upload them as release assets. Use the same signing identity for updates.
The private key uses the same password as the keystore.
Increment `android:versionCode` and update `android:versionName` whenever publishing newly built Android APKs.

Test the final universal APK on a device, including the installation/update
path. Review [the testing checklist](testing.md) and package instructions.
Generate `SHA256SUMS.txt` from the final ZIP and APK files. Tag the verified
commits only after checks pass, then publish the assets and installation link.
The upstream imgui release has a docking tag and a companion `-standard` source
tag; the same example packages can be attached to both repositories' releases.

## Desktop-only patch releases

A desktop fix can be released without rebuilding Android. Run the full portable
workflow for the new source commit and promote the four checked desktop ZIPs.
For unchanged Android code, retain the four signed APKs from the previous
release byte-for-byte. Verify their SHA-256 hashes against that release before
uploading them, and include them in the new `SHA256SUMS.txt`.

State explicitly in the release notes and `BUILD-PROVENANCE.txt` that the APKs
retain their previous source revision, Android version and signing identity.
Do not label retained APKs as builds of the desktop patch. New CI debug APKs
remain test artifacts. An Android change requires new version metadata, signing
and device validation as described above.

Required desktop jobs run `scripts/check_installed_deps.vsh` before building.
It compares every direct and transitive `v.mod` pin with the installed Git tag
commit. The standard lane explicitly selects `antono2.imgui=-standard`; other
lanes must match the declared tags. Keep advisory master jobs separate.
