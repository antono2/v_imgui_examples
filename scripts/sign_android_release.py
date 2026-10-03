#!/usr/bin/env python3
"""Combine CI ABI inputs and sign installable APKs with a private release key."""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--input', type=Path, action='append', required=True,
                    help='Extracted CI artifact directory with unsigned APK and licenses')
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--build-tools', type=Path, required=True)
parser.add_argument('--keystore', type=Path, required=True)
parser.add_argument('--password-file', type=Path, required=True)
parser.add_argument('--alias', default='v-imgui-release')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
shared = None
libraries = {}
notices = {}
for folder in args.input:
    apk = folder / 'vimgui-demo-unsigned.apk'
    with zipfile.ZipFile(apk) as archive:
        common = {}
        for name in archive.namelist():
            if name.endswith('/') or name.startswith('META-INF/'): continue
            data = archive.read(name)
            if name.startswith('lib/'):
                if not re.fullmatch(r'lib/(armeabi-v7a|arm64-v8a|x86_64)/[^/]+\.so', name):
                    raise ValueError(f'Unexpected native library path: {name}')
                if name in libraries: raise ValueError(f'Duplicate native input: {name}')
                libraries[name] = data
            else:
                common[name] = data
        if shared is None: shared = common
        elif shared != common: raise ValueError('ABI inputs disagree on the manifest, UI classes or assets')
    for file in (folder / 'licenses').rglob('*'):
        if not file.is_file(): continue
        name = 'assets/licenses/' + file.relative_to(folder / 'licenses').as_posix()
        if name in notices and notices[name] != file.read_bytes():
            raise ValueError(f'License inputs disagree: {name}')
        notices[name] = file.read_bytes()
abis = {name.split('/')[1] for name in libraries}
if abis != {'armeabi-v7a', 'arm64-v8a', 'x86_64'}:
    raise ValueError(f'Expected all three supported ABIs, got {abis}')
for abi in abis:
    expected = {f'lib/{abi}/{name}' for name in ('libvimgui.so', 'libvimgui_android_demo.so', 'libvimgui_android_ui.so')}
    if {name for name in libraries if name.split('/')[1] == abi} != expected:
        raise ValueError(f'Incomplete ABI: {abi}')
with tempfile.TemporaryDirectory() as temporary:
    temporary = Path(temporary)
    for variant in ['universal', *sorted(abis)]:
        unsigned = temporary / 'unsigned.apk'
        aligned = temporary / 'aligned.apk'
        output = args.output / f'v-imgui-touch-{variant}.apk'
        with zipfile.ZipFile(unsigned, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for name, data in sorted({**shared, **notices, **libraries}.items()):
                if name.startswith('lib/') and variant != 'universal' and name.split('/')[1] != variant: continue
                entry = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
                entry.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(entry, data)
        subprocess.run([str(args.build_tools / 'zipalign'), '-f', '-p', '4', str(unsigned), str(aligned)], check=True)
        subprocess.run([str(args.build_tools / 'apksigner'), 'sign', '--ks', str(args.keystore),
                        '--ks-key-alias', args.alias, '--ks-pass', 'file:' + str(args.password_file),
                        '--key-pass', 'file:' + str(args.password_file), '--out', str(output), str(aligned)], check=True)
        subprocess.run([str(args.build_tools / 'apksigner'), 'verify', '--verbose', str(output)], check=True)
        print(f'{hashlib.sha256(output.read_bytes()).hexdigest()}  {output.name}')
