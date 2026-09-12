# CLAUDE.md — repo guidance

Snipcast is a native macOS menu bar screen recorder: hotkey → drag a region → record via
ScreenCaptureKit → trim in AVKit → hand the file to Messages. Tangent Labs app
(`com.tangentlabs.snipcast`, team `4T3PRTK36U`). No App Store or sandbox for now.

## Conventions

- The Xcode project is generated: edit `project.yml`, run `xcodegen generate`. Never hand-edit
  `Snipcast.xcodeproj` (it is gitignored).
- Swift 6 language mode with strict concurrency. UI and capture state are `@MainActor`;
  framework delegate callbacks are `nonisolated` and hop back with `Task { @MainActor in }`.
- Keep pure logic (geometry, naming, size rules) in static helpers so it stays testable
  without a screen. Tests use Swift Testing (`import Testing`), not XCTest.
- Screen Recording permission is keyed to the signed bundle; keep signing on the team
  certificate so rebuilds don't re-prompt.
- Menus on macOS 27 hide symbol images by default; don't rely on icons in menu items.

## Build / test

```bash
xcodegen generate
xcodebuild -project Snipcast.xcodeproj -scheme Snipcast -derivedDataPath build/DerivedData build
xcodebuild -project Snipcast.xcodeproj -scheme Snipcast -derivedDataPath build/DerivedData test
```

## Verification

Capture cannot be unit-tested. To prove a capture change works, launch the built app,
record a region, and check the file in `~/Movies/Snipcast/` (`ffprobe` or QuickTime).
See `docs/adr/` for the decisions behind the capture and trim pipeline.
