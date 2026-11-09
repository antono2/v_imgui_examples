# Audio playground

A native spatial-audio demonstration of [`antono2.audio`](https://github.com/antono2/audio),
using `antono2.imgui`, `antono2.glfw` and `antono2.vulkan` for its desktop interface.
Move the sound around the listener, change volume and see the corresponding V call.
The sound comes from the native audio library; the diagram displays position.

From the repository root:

```sh
python3 scripts/build_audio_playground.py --run
```

Use `python` on Windows. The builder downloads pinned public source dependencies
into `build/audio/`, leaving installed V modules alone. Install system prerequisites
first; see [build, controls and validation](../../docs/audio-playground.md).

The window starts silent at 10% volume. Press **Play** when ready. **Stop** and
**Escape** stop playback; losing focus also stops playback. **Mute** restores the
previous volume when pressed again. **Reset** stops sound and restores defaults.
Use the presets, drag the sound, or expand **Position values & V call** for sliders.

At higher OS scaling or smaller window sizes the controls move above the diagram.
Buttons wrap and the window scrolls vertically when necessary. Tab and Shift+Tab
navigate native widgets; Space activates the focused control. **P** toggles playback,
**1/2/3** select positions, **M** mutes, **R** resets, and **+/-** adjusts volume.

To stream your own mono WAV or Ogg/Vorbis file:

```sh
build/audio_playground --file /path/to/mono.ogg
```

The bundled chime is original MIT-licensed audio by Anton Oreskin, reproducible
with `python3 scripts/generate_audio_chime.py`. Stereo files are rejected because
this example demonstrates spatial placement of a mono source.

This is a desktop source example. It is not yet included in the existing release
ZIPs or the Android example.
