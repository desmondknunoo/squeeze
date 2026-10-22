# Squeeze — To do

_Last updated: 2026-10-22_

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
- [ ] Review and commit the uncommitted work on `develop`: `VideoCompressorApp.swift` renamed to `SqueezeApp.swift` (staged), changes to `ContentView.swift`, `Info.plist` and `build.sh`, and new `AppSettings.swift`, `SettingsView.swift`, `Assets/`, `README.md`, `dist.sh`
- [ ] Decide whether `ui/` (design mockup PNGs) belongs in the repo; the README points to it
- [ ] Publish a GitHub release with `Squeeze-1.0-macOS-arm64.dmg`; the README links to Releases but none exists
- [ ] Open a pull request from `develop` to `main` once committed (README workflow: `main` only receives merges via PR)
- [ ] Sign with a Developer ID and notarize so first launch does not need right-click → Open (currently ad-hoc signed)
- [ ] Add tests; there are none (e.g. preset settings, size estimate and output-path logic in `ContentView.swift`)
- [ ] Split `ContentView.swift` (about 80 KB) into smaller files

## Notes
- Uncommitted: `M ContentView.swift`, `M Info.plist`, `M build.sh`, staged rename `VideoCompressorApp.swift -> SqueezeApp.swift`; untracked `AppSettings.swift`, `Assets/`, `README.md`, `SettingsView.swift`, `dist.sh`, `ui/`.
- `develop` and `main` are both at `71184d5` and match `origin` (https://github.com/desmondknunoo/squeeze).
- Requires macOS 13+, arm64, and ffmpeg from Homebrew. Built artefacts are in `dist/` (git-ignored). Bundle id `com.desmondk.squeeze`, version 1.0 (1).
