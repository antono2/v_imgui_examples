"""Measure real miniaudio output through a dedicated, non-physical stereo sink.

Uses a private PulseAudio process when available (CI); otherwise a temporary
PipeWire null sink. Captures neither microphone nor other application audio.
Requires ffmpeg; no third-party Python packages.
"""
from array import array
from contextlib import contextmanager
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import wave

root = Path(__file__).resolve().parents[2]
out = root / 'build/audio-validation/output'
out.mkdir(parents=True, exist_ok=True)
binary = root / 'build/audio_playground'
sink = f'audio-visual-test-{os.getpid()}'

@contextmanager
def isolated_sink():
    if shutil.which('pulseaudio'):
        with tempfile.TemporaryDirectory(prefix='audio-visual-pulse-') as temporary:
            socket = str(Path(temporary) / 'native')
            log = open(out / 'pulse.log', 'w')
            process = subprocess.Popen(['pulseaudio', '-n', '--daemonize=no', '--exit-idle-time=-1',
                '--use-pid-file=no',
                '--load=module-null-sink sink_name=' + sink + ' rate=48000 channels=2',
                '--load=module-native-protocol-unix socket=' + socket + ' auth-anonymous=1'],
                env=dict(os.environ, PULSE_RUNTIME_PATH=temporary), stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 8
                while not Path(socket).exists():
                    assert process.poll() is None, 'Private PulseAudio process failed'
                    assert time.monotonic() < deadline, 'Private PulseAudio socket did not appear'
                    time.sleep(.05)
                yield dict(os.environ, PULSE_SERVER='unix:' + socket, PULSE_SINK=sink)
            finally:
                process.terminate()
                try: process.wait(timeout=5)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
                log.close()
    else:
        def nodes():
            return json.loads(subprocess.check_output(['pw-dump']).decode('utf-8', 'replace'))
        assert not any(n.get('info', {}).get('props', {}).get('node.name') == sink for n in nodes())
        try:
            subprocess.run(['pw-cli', 'create-node', 'adapter', '{ factory.name = support.null-audio-sink node.name = ' + sink + ' media.class = Audio/Sink object.linger = true audio.position = [ FL FR ] }'], check=True, capture_output=True)
            deadline = time.monotonic() + 8
            while not any(n.get('info', {}).get('props', {}).get('node.name') == sink for n in nodes()):
                assert time.monotonic() < deadline
                time.sleep(.05)
            yield dict(os.environ, PULSE_SINK=sink)
        finally:
            for node in nodes():
                if node.get('info', {}).get('props', {}).get('node.name') == sink:
                    subprocess.run(['pw-cli', 'destroy', str(node['id'])], check=True, capture_output=True)

with isolated_sink() as env:
    recording = out / 'native-loopback.wav'
    recording.unlink(missing_ok=True)
    recorder = subprocess.Popen(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-y',
        '-f', 'pulse', '-i', sink + '.monitor', '-t', '18', '-ar', '48000', '-ac', '2',
        '-c:a', 'pcm_s16le', str(recording)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        # PulseAudio's monitor can take longer to deliver samples than its socket
        # takes to appear. Starting playback after a fixed sleep lost the first
        # part of the sequence on CI. Require recorded silence before playback.
        deadline = time.monotonic() + 8
        while not recording.exists() or recording.stat().st_size < 96000:
            assert recorder.poll() is None, 'Loopback recorder exited before capturing samples'
            assert time.monotonic() < deadline, 'Loopback recorder did not become ready'
            time.sleep(.05)
        result = subprocess.run([str(binary), '--audio-check', str(out / 'audio-events.json')],
            env=env, capture_output=True, text=True, timeout=20)
        assert result.returncode == 0, result.stderr
        _, errors = recorder.communicate(timeout=18)
        assert recorder.returncode == 0, errors.decode()
    finally:
        if recorder.poll() is None: recorder.kill(); recorder.wait()

with wave.open(str(recording)) as source:
    assert source.getnchannels() == 2 and source.getframerate() == 48000 and source.getsampwidth() == 2
    samples = array('h', source.readframes(source.getnframes()))
if sys.byteorder != 'little': samples.byteswap()
start = next(i // 2 for i, sample in enumerate(samples) if abs(sample) > 32)
start = max(0, start - 480)
levels = []
for index in range(5):
    segment = samples[(start + index * 96000) * 2:(start + index * 96000 + 86400) * 2]
    assert len(segment) == 172800
    levels.append([math.sqrt(sum(v*v for v in segment[channel::2]) / 86400) / 32768 for channel in [0,1]])
assert levels[0][0] > levels[0][1] * 2.5, levels
assert .94 < levels[1][0] / levels[1][1] < 1.06, levels
assert levels[2][1] > levels[2][0] * 2.5, levels
quiet_ratio = sum(levels[3]) / sum(levels[1])
far_ratio = sum(levels[4]) / sum(levels[1])
assert .43 < quiet_ratio < .57, quiet_ratio
assert .27 < far_ratio < .40, far_ratio
assert max(abs(v) for v in samples) < 32700, 'Clipping'
# Allow a bounded device-buffer drain after Stop; no sustained output is allowed.
tail = samples[(start + int(10.25 * 48000)) * 2:]
assert len(tail) >= 48000, 'Insufficient post-stop capture'
assert max(abs(v) for v in tail) <= 2, 'Audio continues after Stop'
report = dict(backend='native miniaudio via an isolated loopback', microphone=False,
    virtual_server='PulseAudio' if shutil.which('pulseaudio') else 'PipeWire',
    rms=levels, positions=['left','centre','right','quiet','far'],
    quiet_ratio=quiet_ratio, far_ratio=far_ratio, clipping=False, stop_is_silent=True, stop_drain_allowance_ms=250)
(out / 'audio-output.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
