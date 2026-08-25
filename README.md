# SeisView — macOS SEG-Y Seismic Data Viewer

A native macOS viewer for SEG-Y / SGY seismic data, built for **instant display of very large files** (10 GB+, hundreds of thousands of traces). Written in pure Swift with zero third-party dependencies. Inspired by SeiSee on Windows.

Opening a 9.5 GB, 589,248-trace file renders immediately — no full-file scan, no pre-conversion.

## Installation

**Requirements:** macOS 13 (Ventura) or later. Universal binary — runs natively on both Apple Silicon and Intel Macs.

**Interface language:** the application UI is available in English and 简体中文. On first launch it follows your system language; you can switch it at any time under **View → Language**, and the choice is remembered and takes effect immediately. Press **⌘?** to open the built-in bilingual user guide. This documentation is in English.

1. **Download** `SeisView-0.1.0.dmg` from the [latest release](https://github.com/ZDDWLIG/SeisView/releases/latest).
   (A `.zip` is also provided if you prefer it over the disk image.)

2. **Install** — open the `.dmg` and drag `SeisView.app` into your `Applications` folder.

3. **First launch** — macOS Gatekeeper will block the app with a message like *"SeisView.app cannot be opened because the developer cannot be verified."* This is expected: the app is ad-hoc signed but not notarized by Apple (notarization requires a paid Developer ID). To open it:

   **Right-click** (or Control-click) `SeisView.app` → choose **Open** → click **Open** again in the dialog.

   You only need to do this once. Afterwards the app opens normally with a double-click.

   Alternatively, remove the quarantine flag from Terminal:

   ```bash
   xattr -d com.apple.quarantine /Applications/SeisView.app
   ```

4. **Open a file** — use `File → Open` (`⌘O`) and select any `.sgy` / `.segy` file. Custom extensions are accepted too.

> **Note on notarization:** to remove the first-launch prompt entirely, an Apple Developer account ($99/year) is required. With one, replace `codesign --sign -` in `scripts/release.sh` with a Developer ID signature and add `notarytool submit` + `stapler staple`.

## Features

- Variable-density section display (grayscale + seismic blue-white-red palettes)
- Horizontal panning, vertical zoom, gain control (percentile / AGC / per-trace / max-amplitude)
- Trace header inspector (FFID, trace sequence, CDP, offset, sample count, etc., with byte positions)
- Shot-based navigation by FFID
- Multi-file comparison: side-by-side and overlay (e.g. before/after denoising, input + mask)
- Automatic correction of files that declare IBM float but actually store IEEE

## Usage

- Two-finger scroll to pan, pinch to zoom, drag to pan
- `⌘←` / `⌘→` — previous / next shot
- Enter a trace number or FFID in the jump box to navigate directly
- Click any trace to inspect its full 240-byte header in the sidebar

## Why It's Fast

The speed does not come from computing quickly — it comes from **reading almost nothing**:

- **O(1) random access** — SEG-Y's fixed-length record layout means the byte offset of trace *i* is computed directly. Opening a 10 GB file reads only the 3600-byte header; the trace count is derived from the file size. No full-file scan.
- **Only viewport traces are read** — a 1200 px wide window reads at most 1200 traces, regardless of how many the file contains.
- **Parallel `pread`** — each worker thread holds its own file descriptor. `pread` is stateless and inherently thread-safe, which is why 8 threads scale near-linearly.
- **Zooming is delegated to the system** — an 8-bit indexed bitmap plus a palette LUT; zoom goes through texture sampling rather than recomputing data.

Measured on Apple M5 / 16 GB with a 9.57 GB file (589,248 traces, ns=4000, IBM format), using `F_NOCACHE` to force honest cold reads:

| Scenario | Time |
|---|---|
| 1 thread, cold read of one screen | 116.7 ms |
| 8 threads, cold read of one screen | **21.6 ms** |
| 8 threads, page cache hit | **2.5 ms** |
| IBM decode alone (2M samples) | 1.2 ms (≈1.6 GB/s) |

Decoding accounts for under 2% of the time — the bottleneck is entirely I/O. That is why no file pre-conversion and no GPU decoding are needed.

Shot indexing is optimized separately: naively scanning 589,248 trace headers takes about 57 seconds. Using strided sampling plus binary search for shot boundaries cuts the number of reads by roughly 30×, finishing in under a second with 8 threads. Results are cached to disk keyed by path + size + mtime.

**Vertical min/max binning is a correctness requirement, not an optimization** — compressing 4000 samples into 800 px by point-sampling would alias badly and severely distort the section's appearance.

## Robustness

The key difference from SeiSee: **malformed files produce a clear error, never a silently wrong image.**

- **Variable-length traces** — validated by exact divisibility of the file size plus sampled consistency checks. The fixed-length-trace flag is often left unmaintained by writers, so it is treated as corroboration only, not truth. On mismatch the file is rejected rather than displayed incorrectly.
- **IBM declared, IEEE stored** — a batch of samples is decoded both ways and the resulting distributions compared for plausibility. The sane interpretation is chosen automatically and flagged as "format auto-corrected" in the status bar.
- **Extended textual headers** — the first-trace offset is adjusted per bytes 3505–3506.
- **Little-endian variants** — if the format code is out of range, little-endian parsing is attempted.
- **Manual override** — ns, format code, and byte order can all be forced explicitly.

Supported data sample format codes: 1 (4-byte IBM float), 2 (4-byte integer), 3 (2-byte integer), 5 (4-byte IEEE float), 8 (1-byte integer).

## Architecture

`SegyKit` has zero UI dependencies, so regression tests can run against real files from the command line instead of relying on visual inspection. Rendering is a pure function `(SegyFile, Viewport) → Image`, meaning any frame can be reproduced exactly in a test.

```
SegyKit (pure core, independently testable)
├── SegyFile      file opening, header parsing, geometry inference and validation
├── TraceReader   parallel pread + sample decoding
├── ShotIndex     FFID shot index construction and on-disk caching
├── Decimator     LOD downsampling (min/max binning)
└── Rasterizer    amplitude → 8-bit index → palette LUT → CGImage

SeisView.app (AppKit + SwiftUI)
├── DocumentModel   open file set + viewport state
├── SectionView     section rendering
├── HeaderInspector trace header table
└── CompareLayout   side-by-side / overlay
```

## Building from Source

Requires macOS 13+ and Swift 6.0+. Command Line Tools are sufficient — **a full Xcode installation is not needed**. Shaders are compiled at runtime, costing only a few tens of milliseconds at startup.

```bash
swift run SeisView           # build and run directly
./scripts/make_app.sh        # build a .app for the current architecture
```

Running the test suite:

```bash
swift run SegyKitTests
```

The golden-file and performance-regression tests need a large SEG-Y file (ns=4000, 589,248 traces). Point `SEGY_BIG_FILE` at one to enable them; without it, those tests are skipped and the rest still run:

```bash
SEGY_BIG_FILE=/path/to/big.segy swift run SegyKitTests
```

## Packaging a Release

```bash
./scripts/release.sh [version]   # defaults to 0.1.0
```

Outputs land in `dist/`:

- `SeisView.app` — universal binary (Apple Silicon + Intel)
- `SeisView-<version>.dmg` — disk image, the recommended distribution format
- `SeisView-<version>.zip`

To regenerate the app icon:

```bash
swift scripts/make_icon.swift && iconutil -c icns Resources/SeisView.iconset -o Resources/SeisView.icns
```

## Known Limitations

- No wiggle-trace display (variable density only)
- Shot indexing may miss boundaries in files where a single shot has fewer than 256 traces
- No spectral analysis, image export, or data write-back (read-only viewer)
- No 3D volume display or slice browsing
- macOS only — no Windows or Linux port

## License

[MIT License](LICENSE.md) © 2026 Tianxiang Gao

Free to use, modify, distribute, and use commercially. The only obligation is to retain the copyright and license notice.
