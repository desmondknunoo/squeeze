# Squeeze

<img src="Assets/logo.png" width="128" alt="Squeeze logo">

Fast, local video compression for macOS. Drop in a video, pick a preset, get a dramatically smaller MP4 — no uploads, no accounts, everything stays on your Mac.

A ~3-minute portrait 1080×1920 file compresses from 432 MB to 68 MB in under 30 seconds (≈7× realtime) at visually lossless quality (SSIM 0.988).

## Requirements

- macOS 13 or later on Apple Silicon (the distributed build is arm64-only)
- [ffmpeg](https://ffmpeg.org) installed via Homebrew:
  ```sh
  brew install ffmpeg
  ```

## Install

Download `Squeeze-1.0-macOS-arm64.dmg` from
[Releases](https://github.com/desmondknunoo/squeeze/releases), mount it,
and drag Squeeze to Applications.

> The build is ad-hoc signed, so the first launch needs right-click → Open.

## Use

1. Drop a video anywhere in the window (or choose a file).
2. Pick a **Compression Level**: High Quality, Balanced, Maximum Compression, or Web Optimized. Each preset shows an estimated output size.
3. The output filename is editable and saves beside the original — one click on **Compress & Save** and you're done.
4. While encoding you'll see live progress with time left and encoding speed. When finished, use **Show in Finder** or start another video.

**Simple vs Advanced:** Simple mode (the default) shows only the essentials. Advanced mode adds a 2×2 preset grid, encoder choice (Hardware H.264 / Hardware HEVC / Software x264), resolution options, an output-size estimate sidebar, full file details, and live encoder stats. Switch anytime in Settings (⌘,).

## Settings

- **General** — default interface (Simple/Advanced)
- **Appearance** — System/Light/Dark, plus theme colour (Red default)
- **Behavior** — check ffmpeg on launch, show/hide compression estimates, ask before replacing existing files

## How it works

- Apple Silicon hardware encoding (`h264_videotoolbox` / `hevc_videotoolbox`) with a tuned software x264 fallback.
- AAC audio is passed through bit-identically; other audio is re-encoded once.
- Resolution choices never upscale, and portrait vs landscape is handled correctly.
- HDR (PQ/HLG) sources are tone-mapped to properly tagged BT.709 SDR.
- Accurate progress from ffprobe duration plus ffmpeg's progress pipe; failed or cancelled runs never leave partial files behind.

## Development

```sh
./build.sh   # builds build/Squeeze.app
./dist.sh    # builds versioned DMG + ZIP + checksums in dist/
```

Workflow: all work happens on `develop`; `main` is protected and only receives merges via pull request (`gh pr create --base main --head develop`).
