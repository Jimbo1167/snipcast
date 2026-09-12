# Snipcast

A macOS menu bar app for recording a region of the screen with one hotkey, trimming it,
and sending the file at full quality through Messages.

**Flow:** press the hotkey (default ⌃⇧R) → drag a rectangle (or press Return to reuse the
last one) → press the hotkey again or click Stop → trim in the review window → **Send with
Messages**.

## Requirements

- macOS 15 or later (uses `SCRecordingOutput`, which writes the capture straight to disk).
- Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Screen Recording permission, granted once under *System Settings › Privacy & Security ›
  Screen & System Audio Recording*.

## Build

```bash
xcodegen generate
xcodebuild -project Snipcast.xcodeproj -scheme Snipcast -configuration Debug -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Snipcast.app
```

Tests:

```bash
xcodebuild -project Snipcast.xcodeproj -scheme Snipcast -derivedDataPath build/DerivedData test
```

The `.xcodeproj` is generated and gitignored; edit `project.yml` instead.

## Layout

| Path | What lives there |
| --- | --- |
| `Snipcast/App` | `@main` menu bar scene, the `AppController` state machine, settings + hotkey names |
| `Snipcast/Capture` | region overlay, ScreenCaptureKit recorder, recording HUD, coordinate math |
| `Snipcast/Editor` | review window (AVKit player with built-in trim) and the trim exporter |
| `Snipcast/Support` | recordings folder + naming, permissions, Messages/Finder/pasteboard sharing |
| `SnipcastTests` | Swift Testing suites for the pure helpers |
| `docs/adr` | architecture decision records |

Recordings are saved to `~/Movies/Snipcast/` as `Snipcast <date> at <time>.mp4`.

## Settings

Codec (HEVC or H.264), frame rate (30/60), cursor visibility, system audio capture, and
frame-accurate trimming (re-encodes) are in the Settings window. Both hotkeys are
rebindable there.
