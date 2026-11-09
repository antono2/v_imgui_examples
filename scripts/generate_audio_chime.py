"""Generate the original MIT-licensed mono chime; Python standard library only."""
import math
from pathlib import Path
import struct
import wave

path = Path(__file__).resolve().parents[1] / 'examples/audio_playground/assets/chime.wav'
samples = []
for i in range(96000):
    t = i / 48000
    # Soft attack, exponential release, with a silent tail for repeated playback.
    envelope = (1 - math.exp(-t * 90)) * math.exp(-t * 6)
    fade = max(0, min(1, (1.2 - t) / .15))
    value = .24 * envelope * fade * (math.sin(math.tau * 440 * t) + .3 * math.sin(math.tau * 660 * t)) / 1.3
    samples.append(round(value * 32767))
with wave.open(str(path), 'wb') as output:
    output.setparams((1, 2, 48000, 0, 'NONE', 'not compressed'))
    output.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
print(path)
