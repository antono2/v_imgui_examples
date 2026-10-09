# Validation follow-up — 2026-10-09

## Linux startup fix

The raw GLFW/Vulkan example now maps its initially hidden window immediately
after creation and waits for visibility before renderer setup. In the affected Xvfb/Openbox/Lavapipe session,
the previous startup could wait inside `vkQueuePresentKHR` before the window
manager mapped it. The wait processes GLFW events and has a five-second limit. Mapping after
renderer setup still timed out once in the standard package keyboard check,
although that package had passed rendering and AT-SPI. Mapping is therefore
completed before Vulkan/ImGui setup adds further X11 requests and events.
The revised host passed twelve local startup/render/exit runs (six without a
window manager, six with Openbox) under Lavapipe with Vulkan validation. The
updated raw demo also passed F11/held-key/restore/Escape checks. Existing gallery
and dashboard binaries passed the remainder of the keyboard suite.

[PR #24](https://github.com/antono2/v_imgui_examples/pull/24) passed all 17 checks:
Linux and Windows builds, the pinned V3 lane, standard and docking portable
packages, keyboard shortcuts, Linux AT-SPI, Windows UI Automation and Android
builds for three ABIs. The earlier interaction results remain in
[the October 3 report](validation-2026-10-03.md).

## Dependency graph verification

Required desktop jobs verify installed tag commits against `v.mod`, recursively
including each dependency's own pins. Standard ImGui requires an explicit
companion-tag selection. Current dependency masters remain advisory.

Local fixtures passed with stable V 0.5.2 and pinned V3
`c0449e860641`: recursive annotated tags and paths containing spaces, rejection
of a mismatched transitive checkout, conflicting pins, implicit companion tags,
unused companion selections and unpinned dependencies; explicit companion
selection passed. The complete release dependency graph also passed locally.

## Release scope

Version 1.0.1 is a desktop patch. Publish the four desktop ZIPs from the passing
portable workflow for this revision and record that run in release provenance.
Retain the signed Android 1.0.0 APKs unchanged, verify their original hashes and
record their earlier provenance. This patch does not claim another Android
device session or new TalkBack/Narrator speech validation. Automated provider
checks establish actions and state, not spoken announcement quality.
