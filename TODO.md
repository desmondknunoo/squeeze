# Squeeze — To do

_Last updated: 2026-10-27_

Local video compressor for macOS on Apple Silicon: drop in a video, pick a preset, get a smaller MP4 via ffmpeg with hardware encoding. SwiftUI app built with `swiftc` scripts (no Xcode project); 1.0 committed on 2026-09-27, with the rename to Squeeze, Settings and a redesigned interface still uncommitted.

## Done
- Hardware H.264/HEVC encoding (`videotoolbox`) with a software x264 fallback, driven by ffmpeg/ffprobe
- Four compression presets with output-size estimates; never upscales; portrait and landscape handled
- AAC audio passed through; HDR (PQ/HLG) tone-mapped to BT.709 SDR
- Live progress with time left and encoding speed; failed or cancelled runs leave no partial files
- Simple and Advanced interface modes; Settings window (General, Appearance with theme colour, Behavior)
- App icon and logo; `build.sh` builds an ad-hoc signed `Squeeze.app`, `dist.sh` builds a versioned DMG, ZIP and SHA-256 checksums
- README with requirements, install, usage and development workflow

## To do
- [x] Review and commit the Squeeze rename, Settings, redesigned UI, icon, README and `dist.sh` on `develop` (2026-10-27)
- [x] Keep `ui/` (15 MB of mockup PNGs) out of git: added to `.gitignore`, README pointer removed
- [x] Refuse an output filename that resolves to the original video. ffmpeg refused to overwrite its input and the failure path then deleted the output path, which was the original (`isSameFile` in `ContentView.swift`)
- [ ] Build in Xcode to confirm the change compiles; this Mac has only the Command Line Tools, so only the new `isSameFile` helper was compiled and tested on its own
- [ ] Make Cancel work during "Probing file…": `currentProcess` is set only after probing, so Cancel does nothing and the encode still starts; cancelling just before `process.run()` calls `terminate()` on an unlaunched process and can crash
- [ ] Report cancelled runs as cancelled: ffmpeg exits 255 on SIGTERM, so the `SIGTERM` check never matches and the user sees "Compression failed (exit 255)."
- [ ] Add `cd "$(dirname "$0")"` to `build.sh` and `dist.sh`; run from another folder, `rm -rf build` / `dist` removes that folder's directory
- [ ] Have `dist.sh` write `VERSION` into `Info.plist`; `VERSION=1.1 ./dist.sh` names the DMG 1.1 while the app still says 1.0
- [ ] Remove the camera, microphone and Apple Events usage descriptions from `Info.plist`; the app uses none of them
- [ ] "Advanced ›" and the play button change the saved Settings default, not just the current view
- [ ] Publish a GitHub release with `Squeeze-1.0-macOS-arm64.dmg`; the README links to Releases but none exists
- [ ] Open a pull request from `develop` to `main` once committed (README workflow: `main` only receives merges via PR)
- [ ] Sign with a Developer ID and notarize so first launch does not need right-click → Open (currently ad-hoc signed)
- [ ] Add tests; there are none (e.g. preset settings, size estimate and output-path logic in `ContentView.swift`)
- [ ] Split `ContentView.swift` (about 80 KB) into smaller files

## Notes
- `ui/` holds the design mockups locally and is git-ignored.
- `develop` is ahead of `main` (https://github.com/desmondknunoo/squeeze); open the PR to merge.
- Requires macOS 13+, arm64, and ffmpeg from Homebrew. Built artefacts are in `dist/` (git-ignored). Bundle id `com.desmondk.squeeze`, version 1.0 (1).
