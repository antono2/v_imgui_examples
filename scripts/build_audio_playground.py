"""Build the audio example with pinned, isolated antono2 modules and V.

Downloads source dependencies; never installs packages or changes user modules.
Use --check for prerequisite checks without downloading or compiling anything.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
pins = json.loads((root / 'examples/audio_playground/dependencies.json').read_text())
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--modules', type=Path, default=root / 'build/audio/modules')
parser.add_argument('--compiler', type=Path, help='Explicit compatible V compiler; otherwise bootstrap the pinned V1 compiler')
parser.add_argument('--check', action='store_true')
parser.add_argument('--run', action='store_true')
parser.add_argument('--test-model', action='store_true', help='Compile and run state model tests after building')
args = parser.parse_args()
windows = os.name == 'nt'
cc = os.environ.get('ANTONO2_AUDIO_V_CC') or ('gcc' if windows else 'cc')
cxx = os.environ.get('CXX') or ('g++' if windows else 'c++')
for tool in ['git', 'cmake', cc, cxx]:
    if not shutil.which(tool): raise SystemExit(f'Missing {tool}; see docs/audio-playground.md.')
if args.check:
    print('Build tools found. Linux/macOS also need the GLFW development package; see docs/audio-playground.md.')
    raise SystemExit(0)

env = dict(os.environ, V_C_ERROR_BUG_REPORT_DISABLED='1', V_MACOS_V3_NO_FALLBACK='1')
env.pop('VFLAGS', None)


def run(command, cwd=None, child_env=None):
    subprocess.run(list(map(str, command)), cwd=cwd, env=child_env or env, check=True)


def checkout(repository, revision, directory):
    directory.parent.mkdir(parents=True, exist_ok=True)
    if not (directory / '.git').exists():
        if directory.exists() and any(directory.iterdir()):
            raise RuntimeError(f'Refusing to overwrite non-git dependency: {directory}')
        run(['git', 'init', '--quiet', directory])
        run(['git', '-C', directory, 'remote', 'add', 'origin', 'https://github.com/' + repository + '.git'])
    dirty = subprocess.check_output(['git', '-C', str(directory), 'status', '--porcelain', '--untracked-files=no'], text=True)
    if dirty: raise RuntimeError(f'Dependency has local changes: {directory}')
    current = subprocess.run(['git', '-C', str(directory), 'rev-parse', 'HEAD'], capture_output=True, text=True)
    if current.returncode or current.stdout.strip() != revision:
        run(['git', '-C', directory, 'fetch', '--depth', '1', 'origin', revision])
        run(['git', '-C', directory, 'checkout', '--quiet', '--detach', 'FETCH_HEAD'])


modules = args.modules.resolve()
for name, revision in pins['modules'].items():
    checkout('antono2/' + name, revision, modules / 'antono2' / name)
imgui = modules / 'antono2/imgui'
audio = modules / 'antono2/audio'
run(['git', '-C', imgui, 'submodule', 'update', '--init', '--recursive', '--depth', '1', 'cimgui', 'cimplot'])

if args.compiler:
    compiler = args.compiler.resolve()
else:
    toolchain = root / 'build/audio/toolchain/v'
    checkout('vlang/v', pins['v'], toolchain)
    checkout('vlang/vc', pins['vc'], toolchain / 'vc')
    compiler = toolchain / ('v-audio.exe' if windows else 'v-audio')
    if not compiler.exists():
        # Explicit compatibility compiler: long-running UI frames need the GC.
        command = [cc, '-DCUSTOM_DEFINE_v1_fallback', '-w', '-o', compiler]
        if windows:
            command += ['-std=c99', '-municode', toolchain / 'vc/v_win.c', '-ladvapi32', '-lws2_32', '-lbcrypt', '-Wl,--stack=33554432']
        else:
            command += ['-std=gnu11', toolchain / 'vc/v.c', '-lm', '-lpthread']
        run(command)

# The native backend uses Volk and needs headers only, not a link-time loader.
# Give CMake a real headers-only package rather than requiring an installed SDK.
vulkan_config = root / 'build/audio/cmake/Vulkan'
vulkan_config.mkdir(parents=True, exist_ok=True)
headers = (modules / 'antono2/vulkan/c/vendor/include').as_posix()
(vulkan_config / 'VulkanConfig.cmake').write_text(
    'set(Vulkan_FOUND TRUE)\nset(Vulkan_INCLUDE_DIRS "' + headers + '")\n'
    'if(NOT TARGET Vulkan::Headers)\n  add_library(Vulkan::Headers INTERFACE IMPORTED)\n'
    '  set_target_properties(Vulkan::Headers PROPERTIES INTERFACE_INCLUDE_DIRECTORIES "' + headers + '")\nendif()\n')
native = imgui / 'build/audio-playground'
configure = ['cmake', '-S', imgui, '-B', native, '-DCMAKE_BUILD_TYPE=Release',
             '-DCMAKE_C_COMPILER=' + cc, '-DCMAKE_CXX_COMPILER=' + cxx,
             '-DVIMGUI_OUTPUT_DIR=' + str(imgui / 'lib'), '-DCIMGUI_NO_EXPORT=OFF',
             '-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON', '-DVulkan_DIR=' + str(vulkan_config)]
if windows:
    configure += ['-G', 'Ninja', '-DVIMGUI_GLFW_PROVIDER=bundled', '-DVIMGUI_GLFW_VERSION=3.4']
else:
    configure += ['-DVIMGUI_GLFW_PROVIDER=system']
run(configure)
run(['cmake', '--build', native, '--config', 'Release', '--parallel', '2'])

build_env = dict(env, VMODULES=str(modules), ANTONO2_AUDIO_V_CC=cc,
                 ANTONO2_AUDIO_CC=cc, ANTONO2_AUDIO_AR=os.environ.get('ANTONO2_AUDIO_AR', 'ar'))
if windows:
    header = next((native / '_deps').rglob('include/GLFW/glfw3.h'))
    glfw_lib = next((native / '_deps').rglob('libglfw3.dll.a'))
    build_env.update(GLFW_INCLUDE=str(header.parents[1]), GLFW_LIB=str(glfw_lib.parent))
else:
    prefix = '/usr'
    if sys.platform == 'darwin':
        prefix = subprocess.check_output(['brew', '--prefix', 'glfw'], text=True).strip()
    build_env.setdefault('GLFW_INCLUDE', prefix + '/include')
    library = subprocess.check_output(['pkg-config', '--variable=libdir', 'glfw3'], text=True).strip()
    build_env.setdefault('GLFW_LIB', library)

run([compiler, '-cc', cc, '-gc', 'none', 'run', audio / 'scripts/build_native_audio.vsh'], child_env=build_env)
output = root / 'build' / ('audio_playground.exe' if windows else 'audio_playground')
output.parent.mkdir(exist_ok=True)
staging = output.with_name('audio_playground.building' + ('.exe' if windows else ''))
link_flags = ['-ldflags', '-lm'] if sys.platform.startswith('linux') else []
run([compiler, '-no-memory-limit', '-gc', 'boehm', '-d', 'use_bundled_libgc', '-cc', cc, *link_flags,
     '-path', str(modules / 'antono2') + '|@vlib|@vmodules', '-o', staging,
     root / 'examples/audio_playground'], child_env=build_env)
staging.replace(output)
if windows:
    for dependency in [*imgui.joinpath('lib').glob('*.dll'), *native.rglob('glfw3.dll')]:
        shutil.copy2(dependency, output.parent / dependency.name)
    compiler_dir = Path(shutil.which(cc)).parent
    for name in ['libstdc++-6.dll', 'libgcc_s_seh-1.dll', 'libwinpthread-1.dll']:
        dependency = compiler_dir / name
        if dependency.exists(): shutil.copy2(dependency, output.parent / name)
if args.test_model:
    run([compiler, '-gc', 'boehm', '-d', 'use_bundled_libgc', '-cc', cc,
         root / 'examples/audio_playground/model/model_test.v'], child_env=build_env)
print('Built ' + str(output))
if args.run: run([output], child_env=build_env)
