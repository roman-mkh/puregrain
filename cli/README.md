# puregrain-cli

Error-diffusion dithering of PNG images from the command line, built on
the puregrain library in this repository. It reads a PNG, dithers it with
a classic error-diffusion kernel (Floyd–Steinberg, Atkinson or
Jarvis–Judice–Ninke), and writes the result as a PNG: 1-bit black and
white, a few gray or color levels, or a fixed palette.

> **Status:** a development tool inside the puregrain workspace. It isn't
> published as a package yet, so run it from a checkout of this repository.

## Quick start

From the repository root:

```bash
npm install               # once: the PureScript toolchain and pngjs
npm run build             # compiles the library and the CLI
npm run generate-images   # test images: samples/gray-512.png, samples/color-512.png

# 1-bit black and white, Floyd–Steinberg
npm run dither-cli -- samples/gray-512.png samples/out-bw.png

# a color image reduced to the 216 web-safe colors
npm run dither-cli -- samples/color-512.png samples/out-websafe.png --palette websafe216

# a color image as 4 levels of gray
npm run dither-cli -- samples/color-512.png samples/out-gray4.png --gray --levels 4
```

View the results at **100% zoom**. Any other zoom level resamples the dot
pattern, averaging dots into grays or creating moiré that isn't in the file.

Everything after `--` is passed to the CLI. You can also call the launcher
directly: `node cli/bin/puregrain-cli.mjs INPUT.png OUTPUT.png ...`. Your
own PNGs work the same way, and `samples/` (gitignored) is a good place to
keep them.

## Usage

```
puregrain-cli INPUT.png OUTPUT.png [-k|--kernel NAME]
              [--threshold T | --levels N | --palette NAME] [--gray]
```

## Options

| Option | Argument | Default | What it does |
|---|---|---|---|
| `INPUT.png` | path | required | The image to dither: any PNG pngjs can decode (grayscale, RGB, indexed, with or without alpha). Alpha is ignored. |
| `OUTPUT.png` | path | required | Where to write the result. An existing file is overwritten; the directory must already exist. |
| `-k`, `--kernel` | `floyd-steinberg`, `atkinson`, `jjn` | `floyd-steinberg` | The error-diffusion kernel. See [Kernels](#kernels). |
| `--threshold` | number `T` | `128` | 1-bit gray: a pixel, with the error diffused into it, becomes black below `T` and white otherwise. |
| `--levels` | whole number `N` ≥ 2 | | `N` evenly spaced levels from 0 to 255. Gray input gets `N` grays; color input gets `N` levels per channel (up to `N`³ colors). |
| `--palette` | `bw`, `websafe216`, `cga16`, `ansi16`, `ansi256`, `c64`, `zx-spectrum` | | Each pixel becomes the nearest palette color, with all three channels chosen together. See [Palettes](#palettes). |
| `--gray` | | off | Converts a color input to gray before dithering. |
| `-h`, `--help` | | | Shows the help and exits. |

`--threshold`, `--levels` and `--palette` are alternatives; give at most
one. With none of them, the CLI behaves as `--threshold 128`.

## How the output is chosen

| Mode | Gray input (or `--gray`) | Color input |
|---|---|---|
| `--threshold T` (default) | gray, 1-bit | converted to gray, then 1-bit |
| `--levels N` | gray, `N` levels | each channel on its own, `N` levels per channel |
| `--palette NAME` | whole pixel → nearest palette color | whole pixel → nearest palette color |

- **Gray or color?** An input counts as gray when every pixel has
  r = g = b, whatever color type the PNG file declares.
- **Output file type:** gray results are written as 8-bit grayscale PNGs,
  everything else as 8-bit RGB PNGs. Alpha is never written.
- **Per channel versus whole pixel.** There are two ways to dither color:
  - `--levels` treats red, green and blue as three independent gray
    images (the project calls this *scalarED*).
  - `--palette` picks one palette color for the whole pixel, comparing all
    three channels at once (*vectorED*). That's the only way to reach a
    palette that isn't a regular grid of per-channel levels.
- **Gray conversion** (`--gray`, or `--threshold` on a color input) uses
  Rec. 601 luma, 0.299 R + 0.587 G + 0.114 B, on the stored values. A pixel
  that is already gray keeps its exact value. The weighted sum would land
  one floating-point step low for 65 of the 256 gray levels, and that can
  flip a dot exactly at a threshold.

## Kernels

| Name | Error goes to | Character |
|---|---|---|
| `floyd-steinberg` | 4 neighbours: 1 to the right, 3 in the row below | The classic. Fine texture; at tones very near black or white, dots tend to line up into curved diagonal strings ("worms"). |
| `atkinson` | 6 neighbours over the next 2 rows, but only **3/4** of the error | Throws a quarter of the error away on purpose: crisper, higher contrast, but dark and light tones get pushed toward solid black and white, losing detail there. About 1.5× Floyd–Steinberg's time. |
| `jjn` (Jarvis–Judice–Ninke) | 12 neighbours over the next 2 rows | Error spread widest, for the smoothest texture. Slowest: about 3× Floyd–Steinberg's time. |

The exact weights are in `src/Dither/Kernel.purs`. Time grows with the
number of neighbours, because each one costs the same per pixel; the
measurements are in [the benchmarks](../docs/benchmarks-dithering.md).

## Palettes

| Name | Colors | What it is |
|---|---:|---|
| `bw` | 2 | Black and white |
| `websafe216` | 216 | The web-safe colors |
| `cga16` | 16 | The IBM PC palette (CGA, EGA/VGA default, DOS/Linux console) |
| `ansi16` | 16 | The 16 ANSI terminal colors, as xterm's defaults |
| `ansi256` | 256 | xterm's 256 colors |
| `c64` | 16 | Commodore 64 |
| `zx-spectrum` | 15 | ZX Spectrum, normal and bright |

Where each palette's values come from, and notes on each, are in
[docs/palettes.md](../docs/palettes.md). Three things matter when using
the CLI:

- **`bw` goes by RGB distance, not brightness.** Pure green comes out
  black. To go by brightness, use the default `--threshold` mode or add
  `--gray`.
- **`--palette websafe216` and `--levels 6` produce byte-identical
  files,** and `--levels 6` is a little faster. The same holds for EGA's
  full 64 colors and `--levels 4`.
- **`zx-spectrum` gives each pixel a Spectrum color, not the real
  Spectrum look.** The machine allowed only 2 colors per 8×8 block, which
  this tool doesn't imitate.

## Examples

### Gray

```bash
# the three kernels on the same image
npm run dither-cli -- samples/gray-512.png samples/fs.png  --kernel floyd-steinberg
npm run dither-cli -- samples/gray-512.png samples/atk.png --kernel atkinson
npm run dither-cli -- samples/gray-512.png samples/jjn.png --kernel jjn

# 4 gray levels instead of 2
npm run dither-cli -- samples/gray-512.png samples/gray4.png --levels 4

# a different threshold
npm run dither-cli -- samples/gray-512.png samples/t96.png --threshold 96
```

Moving the threshold doesn't make the image lighter or darker, because
error diffusion preserves the average tone. On `samples/gray-512.png` the
input's average brightness is 135.5, and the outputs average 135.7, 135.5
and 135.4 at thresholds 64, 128 and 192. What changes is the texture, and
where the first dots appear in very dark or very light areas.

### Color

```bash
# 2 levels per channel: the 8 corners of the RGB cube
npm run dither-cli -- samples/color-512.png samples/c8.png --levels 2

# 4 levels per channel: up to 64 colors (also EGA's full palette)
npm run dither-cli -- samples/color-512.png samples/levels4.png --levels 4

# the web-safe palette (same result as --levels 6)
npm run dither-cli -- samples/color-512.png samples/websafe.png --palette websafe216

# pure black and white, chosen per color pixel ...
npm run dither-cli -- samples/color-512.png samples/bw-color.png --palette bw
# ... versus by brightness
npm run dither-cli -- samples/color-512.png samples/bw-gray.png
```

### Retro and terminal palettes

```bash
npm run dither-cli -- samples/color-512.png samples/cga.png --palette cga16
npm run dither-cli -- samples/color-512.png samples/c64.png --palette c64
npm run dither-cli -- samples/color-512.png samples/zx.png  --palette zx-spectrum

# xterm's 256 colors, e.g. as the basis for terminal art
npm run dither-cli -- samples/color-512.png samples/xterm.png --palette ansi256
```

A different kernel changes the character of the result as much as the
palette does: try `--kernel atkinson` with `c64` or `zx-spectrum`.

### Shortcuts

`package.json` has ready-made scripts, all writing to `samples/output-*.png`:

| Script | Runs |
|---|---|
| `npm run dither:fs` / `dither:atkinson` / `dither:jjn` | `gray-512.png`, 1-bit, with that kernel |
| `npm run dither:color:levels` | `color-512.png` with `--levels 4` |
| `npm run dither:color:websafe` | `color-512.png` with `--palette websafe216` |
| `npm run dither:color:bw` | `color-512.png` with `--palette bw` |

## Output and timing

The CLI reports each step on standard output:

```
Read samples/gray-512.png: 512x512, gray
Dithered in 2507.2 ms (floyd-steinberg, threshold 128.0, gray)
Wrote samples/out-bw.png (grayscale PNG)
```

The `Dithered in` time covers the dithering only. It excludes PNG
decoding and encoding, gray conversion and Node startup, so it's the
number to use for benchmarks. Expect it to vary noticeably from run to
run; compare the median of several runs. Error messages go to standard
error.

## Exit codes

| Code | When |
|---|---|
| `0` | Success, or `--help`. |
| `1` | Anything else: invalid options, an input that can't be read or decoded, an output that can't be written, or the CLI not built yet. |

## Limitations

- PNG only.
- Alpha is ignored on input and never written.
- Error is diffused on the stored, gamma-encoded sRGB values rather than
  linear light, which skews mid-tones slightly; fixing this is planned.
- Palette matching uses plain RGB distance, which isn't perceptual (see
  `bw` above).
- Rows are always scanned left to right. Alternating the direction
  ("serpentine" scanning) would reduce some directional artifacts.
- It's pure PureScript on Node: about 10 µs per pixel with Floyd–Steinberg
  and a threshold, so roughly 2.6 s for 512×512 and 11 s for 1024×1024 on
  the development machine. Details, and every mode and kernel, are in
  [the benchmarks](../docs/benchmarks-dithering.md).

## Development

- The CLI is the `puregrain-cli` package of the spago workspace
  (`cli/spago.yaml`), depending on the `puregrain` library package. Its
  sources are in `cli/src/Puregrain/Cli/`:
  - `Main.purs` does the I/O: reads the input, times the dithering, writes
    the output.
  - `Pipeline.purs` makes the decisions, as pure functions: gray or color
    processing, which quantizer, and the gray conversion.
  - `Options.purs` parses the command line with the `optparse` package, a
    port of Haskell's optparse-applicative. Each kernel and palette name is
    defined once there; the parser and the help text are derived from it.
  - `Png.purs` and `Png.js` read and write PNGs through pngjs. This is the
    only JavaScript in the package.
- Tests live in `cli/test/`. `OptionsSpec` checks the command-line
  contract documented here (defaults, options, rejected command lines,
  exit codes) on the real parser. `PipelineSpec` checks the "How the output
  is chosen" table and the gray conversion. `npm test` runs them together
  with the library's tests.
- `cli/bin/puregrain-cli.mjs` is the launcher. It runs the compiled code
  from `output/` without rebuilding, so run `npm run build` after changing
  any source.
- `npm run check:cli` runs end-to-end checks of exact properties, such as
  "`--palette websafe216` and `--levels 6` give identical files". They are
  described in [Test images → Exact checks](../docs/test-images.md#exact-checks).
- What the test images contain and what to look for:
  [docs/test-images.md](../docs/test-images.md).
