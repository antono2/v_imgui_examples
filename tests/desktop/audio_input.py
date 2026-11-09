"""Exercise actual GLFW/ImGui input on an isolated 1080p X11 display.

Requires Xvfb, xrdb, xdotool and ImageMagick. Never touches the user's display.
The app reports observations only; controls receive real OS events.
"""
import argparse
import json
import os
from pathlib import Path
import select
import subprocess
import tempfile
import time

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--dpi', type=int, nargs='+', default=[96, 105, 120, 144, 192])
args = parser.parse_args()
assert all(72 <= dpi <= 240 for dpi in args.dpi)
output = root / 'build/audio-validation/input'
output.mkdir(parents=True, exist_ok=True)


def wait(predicate, label, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.04)
    raise AssertionError('Timed out: ' + label)


def check(dpi, env):
    folder = output / f'dpi-{dpi}'
    folder.mkdir(exist_ok=True)
    report = folder / 'state.json'
    report.unlink(missing_ok=True)
    subprocess.run(['xrdb', '-merge'], input=f'Xft.dpi: {dpi}\n', text=True, env=env, check=True)
    subprocess.run(['xdotool', 'mousemove', '1910', '1070'], env=env, check=True)
    with open(folder / 'window.log', 'w') as log:
        app = subprocess.Popen([str(root / 'build/audio_playground'), '--input-check', str(report)],
                               env=env, stdout=log, stderr=log)
        window = None
        try:
            def snapshot():
                assert app.poll() is None, (folder / 'window.log').read_text()
                try:
                    data = json.loads(report.read_text())
                    assert not data['error'], data['error']
                    return data
                except (FileNotFoundError, json.JSONDecodeError):
                    return None

            def state(predicate, label):
                def matches():
                    s = snapshot()
                    return s if s and predicate(s['state']) else None
                return wait(matches, label)

            first = wait(snapshot, 'initial state')
            assert abs(first['scale'] - dpi / 96) < .01, first
            assert first['width'] <= 1840 and first['height'] <= 1000, first
            assert not first['state']['playing'] and abs(first['state']['gain'] - .1) < .001
            if dpi == 192: assert first['stacked']
            ids = subprocess.check_output(['xdotool', 'search', '--onlyvisible', '--name',
                r'^Audio playground \| antono2\.audio$'], env=env, text=True).split()
            assert len(ids) == 1, ids
            window = ids[0]

            def xdo(*commands):
                subprocess.run(['xdotool', *map(str, commands)], env=env, check=True,
                               capture_output=True, timeout=8)

            def capture(name):
                time.sleep(.2)
                subprocess.run(['import', '-display', env['DISPLAY'], '-window', window,
                    str(folder / (name + '.png'))], env=env, check=True, timeout=15)

            def point(name, rx=.5, ry=.5):
                # GLFW window coordinates are already physical pixels on X11.
                # Do not apply the font/content scale a second time.
                current = wait(snapshot, 'geometry')
                r = current['items'][name]
                x, y = r['x'] + r['w'] * rx, r['y'] + r['h'] * ry
                assert 0 <= x < current['width'] and 0 <= y < current['height'], (name, r, current)
                return round(x), round(y)

            def move(name, rx=.5, ry=.5):
                xdo('mousemove', '--window', window, *point(name, rx, ry))

            def click(name, rx=.5, ry=.5):
                move(name, rx, ry)
                xdo('mousedown', 1)
                time.sleep(.06)
                xdo('mouseup', 1)
                time.sleep(.08)

            def top():
                xdo('mousemove', '--window', window, 12, 12, 'click', '--repeat', 30, '--delay', 12, 4)
                wait(lambda: (s := snapshot()) and s['scroll_y'] == 0, 'scroll to top')

            def reveal(name):
                for _ in range(35):
                    current = wait(snapshot, 'scroll geometry')
                    r = current['items'].get(name)
                    if r and r['visible'] and r['y'] >= 12 and r['y'] + r['h'] < current['height'] - 12:
                        return
                    direction = 4 if r and r['y'] < 12 else 5
                    xdo('mousemove', '--window', window, 12, current['height'] // 2,
                        'click', direction)
                    time.sleep(.08)
                raise AssertionError('Cannot reach ' + name)

            xdo('windowfocus', '--sync', window)
            capture('initial')
            for name, x in [('right', 4), ('centre', 0), ('left', -4)]:
                click(name)
                state(lambda s: s['x'] == x and s['z'] == -1, name + ' preset')
            for rx, ry in [(.05, .05), (.95, .05), (.05, .95), (.95, .95), (.5, .5)]:
                click('play', rx, ry)
                state(lambda s: s['playing'], 'play button edge')
                click('stop', rx, ry)
                state(lambda s: not s['playing'], 'stop button edge')
            move('play')
            xdo('mousedown', 1)
            time.sleep(.15)
            assert not wait(snapshot, 'held button')['state']['playing']
            move('stop')
            xdo('mouseup', 1)
            time.sleep(.15)
            assert not wait(snapshot, 'cancelled button')['state']['playing']
            click('volume', .75)
            state(lambda s: .72 < s['gain'] < .79, 'native slider')
            click('mute')
            state(lambda s: s['gain'] == 0, 'mute')
            click('mute')
            state(lambda s: .72 < s['gain'] < .79, 'restore volume')
            reveal('field')
            move('field', .25, .25)
            xdo('mousedown', 1)
            time.sleep(.1)
            move('field', .75, .75)
            time.sleep(.1)
            xdo('mouseup', 1)
            state(lambda s: abs(s['x'] - 3) < .08 and abs(s['z'] - 3) < .08, 'field drag')
            top()
            click('reset')
            state(lambda s: s['x'] == -3 and s['z'] == -2 and abs(s['gain'] - .1) < .001, 'reset')
            # Native keyboard navigation must work independently of shortcuts.
            for _ in range(30):
                current = wait(snapshot, 'keyboard focus')
                if current['items']['play']['focused']: break
                xdo('key', 'Tab')
                time.sleep(.08)
            else: raise AssertionError('Play is unreachable with Tab')
            xdo('key', 'space')
            state(lambda s: s['playing'], 'Space activates focused Play')
            time.sleep(.1)
            assert wait(snapshot, 'focus after label change')['items']['play']['focused']
            xdo('key', 'space')
            time.sleep(.1)
            assert wait(snapshot, 'keyboard restart')['state']['playing']
            xdo('key', 'Escape')
            state(lambda s: not s['playing'], 'Escape after native keyboard activation')
            xdo('key', 'p')
            state(lambda s: s['playing'], 'keyboard play')
            xdo('key', 'Escape')
            state(lambda s: not s['playing'], 'keyboard stop')
            click('play')
            state(lambda s: s['playing'], 'play before focus loss')
            xdo('windowfocus', 0)
            state(lambda s: not s['playing'], 'focus loss stops audio')
            xdo('windowfocus', '--sync', window)

            xdo('windowsize', '--sync', window, 960, 700)
            wait(lambda: (s := snapshot()) and s['width'] == 960 and s['height'] == 700, 'resize')
            top()
            if dpi > 96: assert wait(snapshot, 'resized layout')['stacked']
            capture('compact')
            for name, x in [('right', 4), ('left', -4)]:
                reveal(name)
                click(name, .95, .95)
                state(lambda s: s['x'] == x, 'preset after resize')
            reveal('details')
            if 'x' not in wait(snapshot, 'details state')['items']:
                click('details')
            reveal('x')
            click('x', .75)
            state(lambda s: 2.7 < s['x'] < 3.5, 'reachable advanced slider')
            reveal('field')
            capture('compact-scrolled')
            top()
            reveal('play')
            click('play')
            state(lambda s: s['playing'], 'play after resize')
            reveal('stop')
            click('stop')
            state(lambda s: not s['playing'], 'stop after resize')
            if dpi == 192:
                xdo('windowsize', '--sync', window, 560, 700)
                wait(lambda: (s := snapshot()) and s['width'] == 560, 'narrow window')
                top()
                current = wait(snapshot, 'wrapped buttons')
                assert current['items']['reset']['y'] > current['items']['play']['y']
                capture('narrow-wrapped')
                reveal('right')
                click('right')
                state(lambda s: s['x'] == 4, 'wrapped preset')
                reveal('reset')
                click('reset')
                state(lambda s: s['x'] == -3 and abs(s['gain'] - .1) < .001, 'wrapped reset')
            xdo('key', 'F12')
            assert app.wait(timeout=10) == 0, (folder / 'window.log').read_text()
            errors = (folder / 'window.log').read_text()
            assert not any(word in errors.lower() for word in ['validation error', 'vuid-', 'segmentation', 'fatal']), errors
            return dict(dpi=dpi, scale=first['scale'], initial=[first['width'], first['height']],
                        compact=[960, 700], passed=['work-area fit', 'presets', 'button edges',
                        'release cancellation', 'volume', 'mute restore', 'drag', 'reset',
                        'keyboard', 'focus loss', 'reflow', 'scroll access', 'Vulkan validation'])
        finally:
            if app.poll() is None:
                app.terminate()
                try: app.wait(timeout=5)
                except subprocess.TimeoutExpired: app.kill(); app.wait()


with tempfile.TemporaryDirectory(prefix='imgui-audio-display-') as temporary:
    read_fd, write_fd = os.pipe()
    with open(Path(temporary) / 'xvfb.log', 'w') as log:
        display = subprocess.Popen(['Xvfb', '-displayfd', str(write_fd), '-screen', '0',
            '1920x1080x24', '-noreset', '-nolisten', 'tcp'], pass_fds=(write_fd,), stdout=log, stderr=log)
        os.close(write_fd)
        try:
            assert select.select([read_fd], [], [], 10)[0], 'Xvfb did not start'
            number = os.read(read_fd, 32).decode().strip()
            assert number.isdigit()
            env = dict(os.environ, DISPLAY=':' + number, LIBGL_ALWAYS_SOFTWARE='1')
            env.pop('WAYLAND_DISPLAY', None)
            lavapipe = Path('/usr/share/vulkan/icd.d/lvp_icd.json')
            if lavapipe.exists(): env['VK_DRIVER_FILES'] = str(lavapipe)
            validation = Path('/usr/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json')
            if validation.exists(): env['VK_INSTANCE_LAYERS'] = 'VK_LAYER_KHRONOS_validation'
            results = []
            for dpi in args.dpi:
                results.append(check(dpi, env))
                print(f'PASS: real ImGui input at {dpi / 96:.3f}x on 1080p', flush=True)
            (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        finally:
            os.close(read_fd)
            display.terminate()
            try: display.wait(timeout=5)
            except subprocess.TimeoutExpired: display.kill(); display.wait()
