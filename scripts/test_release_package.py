#!/usr/bin/env python3
"""Extract, relocate and launch a desktop package without a development environment."""

import argparse
import hashlib
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import subprocess
import tarfile
import tempfile
import zipfile


def verify_checksum(archive, checksums):
    entries = []
    for line in checksums.read_text(encoding='utf-8').splitlines():
        match = re.fullmatch(r'([0-9a-fA-F]{64})\s+\*?(.+)', line)
        if match and match[2] == archive.name:
            entries.append(match[1].lower())
    if len(entries) != 1:
        raise ValueError(f'Expected exactly one checksum for {archive.name}')
    digest = hashlib.sha256()
    with archive.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    actual = digest.hexdigest()
    if actual != entries[0]:
        raise ValueError(f'Checksum mismatch: {archive.name}')


def extract(archive, destination):
    # Downloaded archives must contain only relative regular files/directories.
    def safe_name(name):
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or '\\' in name or ':' in name:
            raise ValueError(f'Unsafe archive path: {name}')
    if zipfile.is_zipfile(archive):
        with zipfile.ZipFile(archive) as package:
            for member in package.infolist():
                safe_name(member.filename)
                mode = member.external_attr >> 16
                if stat.S_ISLNK(mode):
                    raise ValueError(f'Archive symlink: {member.filename}')
            package.extractall(destination)
            if os.name != 'nt':
                for member in package.infolist():
                    mode = member.external_attr >> 16
                    if mode & 0o111:
                        (destination / member.filename).chmod(0o755)
    else:
        with tarfile.open(archive) as package:
            members = package.getmembers()
            for member in members:
                safe_name(member.name)
                if not (member.isfile() or member.isdir()):
                    raise ValueError(f'Unsupported archive entry: {member.name}')
            # Preflight above rejects traversal and every link/special entry.
            package.extractall(destination, members=members)


def runtime_environment(home):
    env = dict(os.environ)
    for name in ['VULKAN_SDK', 'VMODULES', 'VEXE', 'V_BIN', 'VTMP', 'GLFW_INCLUDE',
                 'GLFW_LIB', 'IMGUI_DIR', 'LIB', 'LIBPATH', 'INCLUDE',
                 'LD_LIBRARY_PATH', 'LD_PRELOAD', 'PYTHONPATH']:
        env.pop(name, None)
    if os.name == 'nt':
        windows = Path(env.get('SystemRoot', r'C:\Windows'))
        env['PATH'] = os.pathsep.join(map(str, [windows / 'System32', windows]))
        for name in ['APPDATA', 'LOCALAPPDATA', 'USERPROFILE']:
            env[name] = str(home)
    else:
        env['PATH'] = '/usr/bin:/bin'
        env['HOME'] = str(home)
        env['XDG_CONFIG_HOME'] = str(home / 'config')
        env['XDG_DATA_HOME'] = str(home / 'data')
    return env


def run(command, cwd, env, logs, name, timeout, expected=None, expected_code=0):
    log = logs / (name + '.log')
    with log.open('wb') as output:
        process = subprocess.Popen(command, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                   stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=os.name != 'nt',
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run([str(Path(os.environ['SystemRoot']) / 'System32/taskkill.exe'),
                                '/PID', str(process.pid), '/T', '/F'], check=False,
                               stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise RuntimeError(f'{name} timed out; see {log}')
    diagnostics = log.read_text(encoding='utf-8', errors='replace')
    print(diagnostics, end='')
    if code != expected_code or re.search(r'VUID-|validation error|segmentation|assert|fatal', diagnostics, re.I):
        raise RuntimeError(f'{name} failed (exit {code}); see {log}')
    if expected and expected not in diagnostics:
        raise RuntimeError(f'{name} did not report {expected!r}; see {log}')
    print(f'Passed: {name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--project', choices=['torus', 'imgui'], required=True)
    parser.add_argument('--checksums', type=Path)
    parser.add_argument('--logs', type=Path, default=Path('package-smoke-logs'))
    parser.add_argument('--timeout', type=int, default=120)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    archive = args.archive.resolve(strict=True)
    if args.checksums:
        verify_checksum(archive, args.checksums)
    logs = args.logs.resolve()
    logs.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='release consumer with spaces ') as temporary:
        work = Path(temporary)
        extracted = work / 'original extraction'
        extracted.mkdir()
        extract(archive, extracted)
        roots = [path for path in extracted.iterdir() if path.is_dir()]
        if len(roots) != 1 or len(list(extracted.iterdir())) != 1:
            raise ValueError('Expected one top-level package directory')
        package = work / 'relocated package with spaces'
        roots[0].rename(package)
        cwd = work / 'unrelated working directory'
        cwd.mkdir()
        home = work / 'clean user'
        home.mkdir()
        env = runtime_environment(home)
        extension = '.exe' if os.name == 'nt' else ''
        if args.project == 'torus':
            launcher = package / ('torus_trooper.exe' if os.name == 'nt' else 'play.sh')
            launcher.chmod(0o755)
            run([str(launcher), '--headless', '--ticks', '600', '--no-sound', '--volume', '0'],
                cwd, env, logs, 'headless', args.timeout,
                'checksum=490efd84cf12692f' if os.name != 'nt' else None)
            run([str(launcher), '--probe', '--no-sound', '--volume', '0'],
                cwd, env, logs, 'vulkan-probe', args.timeout,
                'GLFW: Vulkan surface creation succeeded' if os.name != 'nt' else None)
            # Published Windows GUI-subsystem builds do not provide console logs.
            # Also require the CLI's documented error exit, to reject a no-op launcher.
            run([str(launcher), '--resolution', 'invalid'], cwd, env, logs,
                'invalid-resolution', args.timeout, expected_code=2)
        else:
            launcher = package / ('examples.exe' if os.name == 'nt' else 'run.sh')
            launcher.chmod(0o755)
            for program in ['examples', 'glfw_vulkan', 'widget_gallery', 'implot_dashboard']:
                (package / (program + extension)).chmod(0o755)
            # The compiled menu supports --help on both platforms. The Linux
            # shell wrapper accepts example names only; exercise it below.
            run([str(package / ('examples' + extension)), '--help'],
                cwd, env, logs, 'launcher-help', args.timeout, 'Usage:')
            for example in ['glfw_vulkan', 'widget_gallery', 'implot_dashboard']:
                env['VIMGUI_SMOKE_FRAMES'] = '660' if example == 'implot_dashboard' else '60'
                run([str(launcher), example], cwd, env, logs, example, args.timeout)
    print('Package passed after relocation, with a clean user and runtime-only PATH.')


if __name__ == '__main__':
    main()
