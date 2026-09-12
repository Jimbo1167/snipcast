# ADR 0001: Record with ScreenCaptureKit's `SCRecordingOutput`, trim by passthrough export

- Status: accepted
- Date: 2026-09-12

## Context

Snipcast needs region recording, a quick trim, and a file that survives iMessage at full
quality. Options considered:

1. Shell out to `screencapture -v`. No region support for video, no control over codec,
   and no programmatic stop signal beyond killing the process.
2. `SCStream` delivering `CMSampleBuffer`s into our own `AVAssetWriter`. Full control, but
   we own the encoder session, timestamps, audio interleaving, and finalization.
3. `SCStream` + `SCRecordingOutput` (macOS 15+). The framework encodes and writes the file;
   we choose the codec, container, and output URL and get start/finish/fail callbacks.

For trimming: `AVAssetExportSession` with the passthrough preset cuts without re-encoding
but snaps to keyframes; a re-encoding preset is frame-accurate but slower and lossy.

## Decision

- Use option 3. Minimum OS is macOS 15. The user's machine runs macOS 26 and Apple's
  ScreenCaptureKit change log lists nothing new in macOS 26 or 27 that would change this.
- Exclude Snipcast's own windows from the content filter so the red frame and stop pill are
  never captured.
- Trim with the passthrough preset by default so the delivered file is bit-identical to the
  capture inside the cut. A "frame-accurate trim" setting switches to the HEVC
  highest-quality preset for the cases where keyframe snapping is unacceptable.
- Default codec is HEVC in an MP4 container: smaller files for the ~100 MB Messages cap and
  supported by every iPhone since 2017. H.264 remains selectable.

## Consequences

- The app cannot run on macOS 14 or earlier.
- Recording finalization is asynchronous; `ScreenRecorder.stop()` waits for the
  `SCRecordingOutputDelegate` finish callback before handing the URL to the editor.
- Passthrough trims can start up to one GOP earlier than the handle position. The setting
  covers the exception rather than making every trim pay for a re-encode.
