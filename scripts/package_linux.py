#!/usr/bin/env python3
"""Stage trusted Linux examples and their non-glibc runtime dependencies."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

BASE = re.compile(r'^(lib(c|m|pthread|dl|rt|resolv|util|mvec)\.so\.|ld-linux|linux-vdso)')
EXAMPLES = ('glfw_vulkan', 'widget_gallery', 'implot_dashboard')


def run(*args):
    return subprocess.check_output(args, text=True, env={**os.environ, 'LD_LIBRARY_PATH': ''})


def dependencies(path):
    result = run('ldd', str(path))
    if 'not found' in result:
        raise RuntimeError(f'Unresolved dependency for {path}:\n{result}')
    for line in result.splitlines():
        match = re.match(r'\s*(\S+) => (/\S+) ', line)
        if match and not BASE.match(match[1]):
            yield match[1], Path(match[2])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binaries', type=Path)
    parser.add_argument('imgui', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--variant', choices=['docking', 'standard'], required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    package = args.output.resolve()
    package.mkdir(parents=True, exist_ok=False)
    lib = package / 'lib'
    notices = package / 'licenses'
    lib.mkdir()
    notices.mkdir()
    queue = []
    for name in EXAMPLES:
        source = args.binaries / name
        shutil.copy2(source, package / name)
        queue.extend(dependencies(source))
    # GLFW loads these with dlopen(), so they do not all appear in ldd.
    for name in ('libvulkan.so.1', 'libXrandr.so.2', 'libXinerama.so.1',
                 'libXcursor.so.1', 'libXi.so.6', 'libXxf86vm.so.1'):
        source = Path('/usr/lib/x86_64-linux-gnu') / name
        if not source.exists():
            raise RuntimeError(f'Missing runtime library: {source}')
        queue.append((name, source))
    copied = {}
    owners = set()
    while queue:
        name, source = queue.pop()
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if name in copied:
            if copied[name] != digest:
                raise RuntimeError(f'Conflicting runtime library: {name}')
            continue
        copied[name] = digest
        shutil.copy2(source, lib / name)
        queue.extend(dependencies(source))
        # Debian/Ubuntu copyright files include upstream license notices.
        candidates = {str(source), str(source.resolve())}
        for candidate in list(candidates):
            if candidate.startswith('/usr/lib/'):
                candidates.add(candidate.removeprefix('/usr'))
            elif candidate.startswith('/lib/'):
                candidates.add('/usr' + candidate)
        for candidate in candidates:
            result = subprocess.run(['dpkg-query', '-S', candidate], text=True, capture_output=True)
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    owner = line.split(': ', 1)[0].split(':')[0]
                    copyright_file = Path('/usr/share/doc') / owner / 'copyright'
                    if copyright_file.exists():
                        owners.add(owner)
    for owner in owners:
        shutil.copy2(Path('/usr/share/doc') / owner / 'copyright', notices / f'{owner}.txt')
    for label, source in {
        'examples': root / 'LICENSE', 'imgui-v': args.imgui / 'LICENSE',
        'imgui': args.imgui / 'cimgui/imgui/LICENSE.txt',
        'cimgui': args.imgui / 'cimgui/LICENSE',
        'implot': args.imgui / 'cimplot/implot/LICENSE',
        'cimplot': args.imgui / 'cimplot/LICENSE',
    }.items():
        shutil.copy2(source, notices / f'{label}.txt')
    subprocess.run(['python3', str(root / 'scripts/collect_licenses.py'), str(args.imgui), str(notices),
                    '--target', 'x86_64-unknown-linux-gnu'], check=True)
    shutil.copy2(root / 'packaging/run.sh', package / 'run.sh')
    (package / 'run.sh').chmod(0o755)
    shutil.copy2(root / 'packaging/README-linux.txt', package / 'README.txt')
    (package / 'VARIANT.txt').write_text(args.variant + '\n')
    (package / 'RUNTIME-LIBRARIES.txt').write_text('\n'.join(sorted(copied)) + '\n')
    for path in [*(package / name for name in EXAMPLES), *lib.iterdir()]:
        subprocess.run(['patchelf', '--set-rpath', '$ORIGIN/lib' if path.parent == package else '$ORIGIN', str(path)], check=True)
    for path in [*(package / name for name in EXAMPLES), *lib.iterdir()]:
        for name, source in dependencies(path):
            if source.parent != lib:
                raise RuntimeError(f'{path.name} depends on an unbundled library: {name} => {source}')
    archive = package.with_suffix('.zip')
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9, strict_timestamps=False) as out:
        for path in sorted(package.rglob('*')):
            if path.is_file():
                out.write(path, path.relative_to(package.parent))
    print(archive)


if __name__ == '__main__':
    main()
