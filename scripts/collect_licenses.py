#!/usr/bin/env python3
"""Collect notices for native sources and the pinned AccessKit Rust graph."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('imgui', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('--target', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
args.output.mkdir(parents=True, exist_ok=True)
for label, source in {
    'examples': root / 'LICENSE', 'imgui-v': args.imgui / 'LICENSE',
    'imgui': args.imgui / 'cimgui/imgui/LICENSE.txt',
    'cimgui': args.imgui / 'cimgui/LICENSE',
    'implot': args.imgui / 'cimplot/implot/LICENSE',
    'cimplot': args.imgui / 'cimplot/LICENSE',
}.items():
    shutil.copy2(source, args.output / f'{label}.txt')
accesskit = args.imgui / '.dependencies/accesskit/accesskit-c-0.23.1'
metadata = json.loads(subprocess.check_output([
    'cargo', 'metadata', '--locked', '--format-version', '1', '--filter-platform', args.target,
    '--manifest-path', str(accesskit / 'Cargo.toml')], text=True, encoding='utf-8'))
notices = []
for package in metadata['packages']:
    folder = Path(package['manifest_path']).parent
    label = f"{package['name']}-{package['version']}"
    destination = args.output / 'rust' / label
    destination.mkdir(parents=True, exist_ok=True)
    notices.append(f"{label}: {package.get('license') or 'See included license file'}")
    (destination / 'SOURCE.txt').write_text(
        f"{label}\nLicense: {package.get('license')}\nSource: {package.get('repository') or package.get('source') or 'AccessKit release source'}\n")
    for file in folder.iterdir():
        if file.is_file() and any(word in file.name.upper() for word in ('LICENSE', 'COPYING', 'NOTICE')):
            shutil.copy2(file, destination / file.name)
    custom = package.get('license_file')
    if custom:
        shutil.copy2(folder / custom, destination / Path(custom).name)
(args.output / 'RUST-DEPENDENCIES.txt').write_text('\n'.join(sorted(notices)) + '\n')
