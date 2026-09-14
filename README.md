# Snipcast

A macOS menu bar app for recording a region of the screen with one hotkey, trimming it,
and sending the file at full quality through Messages.

**Flow:** press the hotkey (default ⌃⇧R) → click a window to snap to it, drag a rectangle,
or press Return to reuse the last one → press the hotkey again or click Stop → trim in the
review window → **Send with Messages**.

While selecting, the window under the cursor is highlighted, and dragged, moved, or resized
edges snap to window and screen edges. Hold ⌘ to place edges freely.

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

### Testing the latest build

The copy in `/Applications` doesn't update when you rebuild. Every running Snipcast also
registers the same global hotkey, so an old copy can silently answer ⌃⇧R. To test current
`main`, quit every copy, build Release, replace the installed app, and launch only that:

```bash
pkill -x Snipcast
xcodegen generate
xcodebuild -project Snipcast.xcodeproj -scheme Snipcast -configuration Release -derivedDataPath build/DerivedData build
rm -rf /Applications/Snipcast.app
ditto build/DerivedData/Build/Products/Release/Snipcast.app /Applications/Snipcast.app
open /Applications/Snipcast.app
```

Check that exactly one copy is running, from `/Applications`:

```bash
pgrep -lf Snipcast.app
```

The build stays signed with the team certificate, so Screen Recording permission carries over.
If macOS asks again, re-enable Snipcast under *Privacy & Security › Screen & System Audio
Recording*.

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
