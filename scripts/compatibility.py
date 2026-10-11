#!/usr/bin/env python3
"""Validate compatibility.json and resolve the pins used by setup and CI."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess


def resolve(root, platform, variant='docking', compiler='stable'):
    pins = json.loads((root / 'compatibility.json').read_text(encoding='utf-8'))
    if pins.get('schema_version') != 1:
        raise ValueError('Unsupported compatibility schema_version')
    for key in ['v', 'vc', 'tcc', 'linux_vc', 'linux_tcc', 'headers', 'volk', 'v3_v', 'v3_vc']:
        if key in pins and not re.fullmatch(r'[0-9a-f]{40}', pins[key]):
            raise ValueError(f'{key} must be an immutable Git commit')
    for key in ['v', 'vc', 'modules', 'glfw', 'ci_sdk', 'ci_runtime']:
        if not pins.get(key):
            raise ValueError(f'Missing compatibility field: {key}')
    dependencies = dict(re.findall(r"'antono2\.([a-z0-9_]+)@([^']+)'", (root / 'v.mod').read_text()))
    for name, tag in dependencies.items():
        if pins['modules'].get(name) != tag:
            raise ValueError(f'v.mod and compatibility.json disagree for {name}: {tag}')
    outputs = {key: value for key, value in pins.items() if isinstance(value, str)}
    for name, tag in pins['modules'].items():
        if not re.fullmatch(r'[a-z0-9_]+', name) or not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:-standard)?', tag):
            raise ValueError(f'Invalid module pin: {name}={tag}')
        outputs['module_' + name] = tag
    if platform == 'linux':
        outputs['vc'] = pins.get('linux_vc', pins['vc'])
        if 'linux_tcc' in pins:
            outputs['tcc'] = pins['linux_tcc']
    if variant == 'standard' and 'module_imgui' in outputs:
        outputs['module_imgui'] = pins['imgui_standard']
    if compiler == 'v3':
        outputs['v'] = pins['v3_v']
        outputs['vc'] = pins['v3_vc']
    # Outputs are single lines read directly by GitHub Actions and PowerShell.
    for key, value in outputs.items():
        if '\n' in value or '\r' in value:
            raise ValueError(f'Multiline compatibility value: {key}')
    return outputs


def verify_installed(outputs, modules):
    for key, tag in outputs.items():
        if not key.startswith('module_'):
            continue
        name = key.removeprefix('module_')
        checkout = modules / 'antono2' / name
        def revision(ref):
            return subprocess.check_output(['git', '-C', str(checkout), 'rev-parse',
                                            '--verify', ref], text=True).strip()
        if revision('HEAD') != revision('refs/tags/' + tag + '^{commit}'):
            raise ValueError(f'Installed {name} does not match {tag}: {checkout}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--platform', choices=['windows', 'linux'],
                        default='windows' if os.name == 'nt' else 'linux')
    parser.add_argument('--variant', choices=['docking', 'standard'], default='docking')
    parser.add_argument('--compiler', choices=['stable', 'v3'], default='stable')
    parser.add_argument('--github-output', type=Path)
    parser.add_argument('--modules', type=Path, help='Also verify installed Git module revisions')
    parser.add_argument('--get', help='Print one resolved field for shell setup helpers')
    args = parser.parse_args()
    outputs = resolve(args.root, args.platform, args.variant, args.compiler)
    if args.modules:
        verify_installed(outputs, args.modules)
    if args.github_output:
        with args.github_output.open('a', encoding='utf-8') as stream:
            for key, value in outputs.items():
                stream.write(f'{key}={value}\n')
    if args.get:
        print(outputs[args.get])
    else:
        print(json.dumps(outputs, indent=2))


if __name__ == '__main__':
    main()
