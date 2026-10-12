# puregrain-cli

Error-diffusion and ordered dithering of PNG images from the command
line, built on the puregrain library in this repository. It reads a PNG,
dithers it with a classic error-diffusion kernel (Floyd–Steinberg, Atkinson
or Jarvis–Judice–Ninke), with ordered (Bayer) dithering, or with both
combined, and writes the result as a PNG: 1-bit black and white, a few gray
or color levels, a fixed palette, or a ZX Spectrum screen, which it can also
write as the Spectrum's own screen file.

> **Status:** a development tool inside the puregrain workspace. It isn't
> published as a package yet, so run it from a checkout of this repository.

## Quick start

From the repository root:

```bash
npm install               # once: the PureScript toolchain and pngjs
npm run build             # compiles the library and the CLI
npm run generate-images   # test images in samples/: gray and color 512×512, color 256×192

# 1-bit black and white, Floyd–Steinberg
npm run dither-cli -- samples/gray-512.png samples/out-bw.png

# a color image reduced to the 216 web-safe colors
npm run dither-cli -- samples/color-512.png samples/out-websafe.png --palette websafe216

# a color image as 4 levels of gray
npm run dither-cli -- samples/color-512.png samples/out-gray4.png --gray --levels 4

# ordered dithering with the 4×4 Bayer map, no error diffusion
npm run dither-cli -- samples/gray-512.png samples/out-bayer4.png --bayer 4 --kernel none

# a ZX Spectrum screen: two colors per 8×8 cell (Atkinson looks best here)
npm run dither-cli -- samples/color-256x192.png samples/out-zx.png --machine zx-spectrum --kernel atkinson
```

View the results at **100% zoom**. Any other zoom level resamples the dot
pattern, averaging dots into grays or creating moiré that isn't in the file.

Everything after `--` is passed to the CLI. You can also call the launcher
directly: `node cli/bin/puregrain-cli.mjs INPUT.png OUTPUT ...`. Your
own PNGs work the same way, and `samples/` (gitignored) is a good place to
keep them.

## Usage

```
puregrain-cli INPUT.png OUTPUT [-k|--kernel NAME]
              [--threshold T | --levels N | --palette NAME] [--bayer N]
              [--machine NAME] [--format NAME] [--gray]
```

## Options

| Option | Argument | Default | What it does |
|---|---|---|---|
| `INPUT.png` | path | required | The image to dither: any PNG pngjs can decode (grayscale, RGB, indexed, with or without alpha). Alpha is ignored. |
| `OUTPUT` | path | required | Where to write the result: a PNG, or the file `--format` names. An existing file is overwritten; the directory must already exist. |
| `-k`, `--kernel` | `floyd-steinberg`, `atkinson`, `jjn`, `none` | `floyd-steinberg` | The error-diffusion kernel; `none` passes no error on. See [Kernels](#kernels). |
| `--threshold` | number `T` | `128` | 1-bit gray: a pixel, with the error diffused into it, becomes black below `T` and white otherwise. |
| `--levels` | whole number `N` ≥ 2 | | `N` evenly spaced levels from 0 to 255. Gray input gets `N` grays; color input gets `N` levels per channel (up to `N`³ colors). |
| `--palette` | `bw`, `websafe216`, `cga16`, `ansi16`, `ansi256`, `c64`, `zx15` | | Each pixel becomes the nearest palette color, with all three channels chosen together. See [Palettes](#palettes). |
| `--bayer` | `N` = 2, 4, 8 or 16 | | Ordered dithering with the `N`×`N` Bayer map, over the `--levels` (2 without it). Pure with `--kernel none`, combined with error diffusion otherwise. See [Ordered dithering](#ordered-dithering). |
| `--machine` | `zx-spectrum` | | Dithers to a machine's screen, where each cell may use only a few colors, chosen per cell. See [Machine screens](#machine-screens). |
| `--format` | `png`, `scr` | `png` | The output file's format. `scr` is the ZX Spectrum's own screen file, for `--machine zx-spectrum` on a 256×192 image. See [Machine screens](#machine-screens). |
| `--gray` | | off | Converts a color input to gray before dithering. |
| `-h`, `--help` | | | Shows the help and exits. |

`--threshold`, `--levels` and `--palette` are alternatives; give at most
one. With none of them, the CLI behaves as `--threshold 128`. `--bayer`
works over levels: give it alone or with `--levels`, not with `--threshold`
or `--palette`. `--machine` defines all the colors itself, so it combines
with none of `--threshold`, `--levels`, `--palette` and `--bayer`;
`--kernel` and `--gray` work with every mode. `--format scr` writes the
ZX Spectrum's screen, so it needs `--machine zx-spectrum`.

## How the output is chosen

| Mode | Gray input (or `--gray`) | Color input |
|---|---|---|
| `--threshold T` (default) | gray, 1-bit | converted to gray, then 1-bit |
| `--levels N` | gray, `N` levels | each channel on its own, `N` levels per channel |
| `--bayer N`, with or without `--levels L` | gray, ordered over `L` levels (2 without `--levels`) | each channel on its own, ordered over `L` levels per channel |
| `--palette NAME` | whole pixel → nearest palette color | whole pixel → nearest palette color |
| `--machine NAME` | the machine's colors, cell by cell | the machine's colors, cell by cell |

- **Gray or color?** An input counts as gray when every pixel has
  r = g = b, whatever color type the PNG file declares.
- **Output file type:** gray results are written as 8-bit grayscale PNGs,
  everything else as 8-bit RGB PNGs. Alpha is never written. With
  `--format scr`, the output is the ZX Spectrum's screen file instead.
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
| `none` | nowhere | No error diffusion: each pixel is decided on its own. With `--bayer`, that's pure ordered dithering. With `--threshold` or `--levels`, each pixel is just rounded to a level (posterization). |

The exact weights are in `src/Puregrain/Kernel.purs`. Time grows with the
number of neighbours, because each one costs the same per pixel; the
measurements are in [the benchmarks](../docs/benchmarks-dithering.md).

## Ordered dithering

`--bayer N` compares each pixel against a threshold that depends on its
position, taken from the `N`×`N` Bayer matrix repeated across the image.

- **Pure, with `--kernel none`:** regular crosshatch patterns, the same for
  the same gray everywhere, and no "worms". An `N`×`N` map gives `N`² + 1
  patterns between two levels: 17 for `--bayer 4`, 65 for `--bayer 8`.
- **Combined with a kernel** (Floyd–Steinberg by default): the Bayer
  pattern decides where the dots land, and error diffusion keeps the tones
  right. The texture is the Bayer one, broken up where diffusion moves a
  dot.
- **Levels and color** work as for `--levels`: `--bayer 4 --levels 4` gives
  4 grays, or 4 levels per channel on color input.
- **Not with palettes.** `--bayer` with `--palette` is rejected: ordered
  dithering against a palette needs a different method. For palettes that
  are a grid of per-channel levels, use `--levels` instead: `--bayer 4
  --levels 6` gives exactly the web-safe colors.

The math, the matrices, and what to look for in the results are in
[docs/ordered-dithering.md](../docs/ordered-dithering.md).

## Palettes

| Name | Colors | What it is |
|---|---:|---|
| `bw` | 2 | Black and white |
| `websafe216` | 216 | The web-safe colors |
| `cga16` | 16 | The IBM PC palette (CGA, EGA/VGA default, DOS/Linux console) |
| `ansi16` | 16 | The 16 ANSI terminal colors, as xterm's defaults |
| `ansi256` | 256 | xterm's 256 colors |
| `c64` | 16 | Commodore 64 |
| `zx15` | 15 | ZX Spectrum colors, normal and bright |

Where each palette's values come from, and notes on each, are in
[docs/palettes.md](../docs/palettes.md). Three things matter when using
the CLI:

- **`bw` goes by RGB distance, not brightness.** Pure green comes out
  black. To go by brightness, use the default `--threshold` mode or add
  `--gray`.
- **`--palette websafe216` and `--levels 6` produce byte-identical
  files,** and `--levels 6` is a little faster. The same holds for EGA's
  full 64 colors and `--levels 4`.
- **`--palette zx15` gives each pixel a Spectrum color, not the real
  Spectrum look.** The machine allowed only 2 colors per 8×8 cell:
  for that, use `--machine zx-spectrum` (see [Machine screens](#machine-screens)).

## Machine screens

`--machine zx-spectrum` dithers to the ZX Spectrum's screen. The screen is
divided into cells of 8×8 pixels, and each cell has two colors: an *ink*
and a *paper*, from the Spectrum's 8 colors, with one BRIGHT bit for both.
So a cell's two colors are both normal or both bright.

- **How each cell gets its colors:** from the 71 pairs (and single colors)
  that look different, the CLI picks the one whose mixes come closest to
  the cell's pixels in the input. A gray cell, for example, gets black and
  white, which can be mixed into gray. Then it dithers inside each cell
  with just those two colors; the error flows on across cell borders as
  usual. A cell that fits several pairs equally well gets the closest
  pair, which gives the calmest result.
- **What it looks like:** where colors change, the 8×8 grid shows, a
  colored edge stepping block by block. On the Spectrum this was called
  *attribute clash*. Inside a cell, smooth shading becomes a dot pattern
  of its two colors.
- **Size:** the Spectrum's screen is 256×192. Other sizes work too for a
  PNG, a poster in the Spectrum's style, say; the CLI then prints a note.
  If the size isn't a multiple of 8, the cells at the right and bottom
  edges are smaller. A screen file (`--format scr`) needs exactly 256×192:
  for any other size the CLI stops with an error before dithering. To
  bring a picture to the screen's size, resize it with another tool first,
  for example ImageMagick (the `!` ignores the aspect ratio):
  `magick photo.png -resize '256x192!' screen.png`.
- **Options:** any `--kernel` works; `--kernel none` gives flat cells,
  with no dots. `--gray` converts the input to gray first. The output is
  an RGB PNG, or with `--format scr` the Spectrum's screen file.
- **Screen file (`--format scr`):** the Spectrum's own format, a copy of
  its screen memory, 6912 bytes: the bitmap, one bit per pixel (1 for the
  ink, 0 for the paper), then one attribute byte per cell. A single-color
  cell has only 0 bits. Emulators open it, for example Fuse, with File →
  Open SCR Screenshot. The CLI writes only the format you choose; for a
  PNG and a screen file, run it twice, as `npm run dither:zx` does. A tape
  image (`.tap`), to load the screen on a Spectrum with `LOAD "" SCREEN$`,
  is planned.
- **Which kernel:** today `--kernel atkinson` looks best. With
  Floyd–Steinberg (the default), thin streaks can appear: a cell can only
  mix along the line between its two colors, so error that points
  elsewhere (green error arriving in a red-and-black cell, say) can't be
  used up there. Floyd–Steinberg passes all of it on, so it builds up to
  the right and downwards, until a cell whose colors can express it turns
  it into a line of extreme pixels. Atkinson passes on only 3/4 of each
  error, so such error dies out.
- **Speed:** like the other color modes, it's several times slower than
  gray dithering; a large poster can take minutes.

The library side is `Puregrain.Cells` (cells of any size, with any
candidate colors) and `Puregrain.Machine.ZxSpectrum` (the Spectrum's
cells and colors, and `toScr` for the screen file).

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
npm run dither-cli -- samples/color-512.png samples/zx15.png --palette zx15   # colors only, see Machine screens

# xterm's 256 colors, e.g. as the basis for terminal art
npm run dither-cli -- samples/color-512.png samples/xterm.png --palette ansi256
```

A different kernel changes the character of the result as much as the
palette does: try `--kernel atkinson` with `c64` or `zx15`.

### Ordered (Bayer)

```bash
# pure ordered dithering with the 4×4 and the 8×8 map
npm run dither-cli -- samples/gray-512.png samples/bayer4.png --bayer 4 --kernel none
npm run dither-cli -- samples/gray-512.png samples/bayer8.png --bayer 8 --kernel none

# the 4×4 map combined with Floyd–Steinberg
npm run dither-cli -- samples/gray-512.png samples/bayer4-fs.png --bayer 4

# color: 4 levels per channel, or exactly the web-safe colors (6 levels)
npm run dither-cli -- samples/color-512.png samples/bayer4-color.png --bayer 4 --kernel none --levels 4
npm run dither-cli -- samples/color-512.png samples/bayer4-websafe.png --bayer 4 --kernel none --levels 6
```

### Machine screens

```bash
# a ZX Spectrum screen, with Floyd–Steinberg (the default) and with Atkinson
npm run dither-cli -- samples/color-256x192.png samples/zx.png --machine zx-spectrum
npm run dither-cli -- samples/color-256x192.png samples/zx-atk.png --machine zx-spectrum --kernel atkinson

# flat cells: each pixel just the nearer of its cell's two colors
npm run dither-cli -- samples/color-256x192.png samples/zx-flat.png --machine zx-spectrum --kernel none

# a poster in the Spectrum's style, at 512×512 (the CLI notes the size)
npm run dither-cli -- samples/color-512.png samples/zx-poster.png --machine zx-spectrum

# the Spectrum's own screen file, for an emulator (256×192 only)
npm run dither-cli -- samples/color-256x192.png samples/zx-atk.scr --machine zx-spectrum --kernel atkinson --format scr
```

### Shortcuts

`package.json` has ready-made scripts, all writing to `samples/output-*`:

| Script | Runs |
|---|---|
| `npm run dither:fs` / `dither:atkinson` / `dither:jjn` | `gray-512.png`, 1-bit, with that kernel |
| `npm run dither:color:levels` | `color-512.png` with `--levels 4` |
| `npm run dither:color:websafe` | `color-512.png` with `--palette websafe216` |
| `npm run dither:color:bw` | `color-512.png` with `--palette bw` |
| `npm run dither:bayer` | `gray-512.png` with `--bayer 4 --kernel none` |
| `npm run dither:bayer:fs` | `gray-512.png` with `--bayer 4`, combined with Floyd–Steinberg |
| `npm run dither:color:bayer` | `color-512.png` with `--bayer 4 --kernel none --levels 4` |
| `npm run dither:zx` | `color-256x192.png` with `--machine zx-spectrum --kernel atkinson`, written as a PNG and as a screen file (`--format scr`) |

## Output and timing

The CLI reports each step on standard output:

```
Read samples/gray-512.png: 512x512, gray
Dithered in 458.1 ms (floyd-steinberg, threshold 128.0, gray)
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
| `1` | Anything else: invalid options, an input that can't be read or decoded, an image that isn't 256×192 for `--format scr`, an output that can't be written, or the CLI not built yet. |

## Limitations

- PNG only, apart from the ZX Spectrum's screen file as output.
- Alpha is ignored on input and never written.
- Error is diffused on the stored, gamma-encoded sRGB values rather than
  linear light, which skews mid-tones slightly; fixing this is planned.
- Palette matching uses plain RGB distance, which isn't perceptual (see
  `bw` above).
- Ordered dithering works over levels only, not against a palette, and
  only with the Bayer maps (the library also takes custom maps).
- Rows are always scanned left to right. Alternating the direction
  ("serpentine" scanning) would reduce some directional artifacts.
- It's pure PureScript on Node: about 2 µs per pixel with Floyd–Steinberg
  and a threshold, so roughly 0.4 s for 512×512 and 2 s for 1024×1024 on
  the development machine. The color modes take about 2 to 5 times as
  long, and ordered dithering without diffusion (`--bayer N --kernel
  none`) about a third. Details, and every mode and kernel, are in
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
    Checks across options that optparse can't express (`--bayer` only with
    `--levels`, `--format scr` only with `--machine zx-spectrum`) are in
    `resolve`, and reported like optparse's own errors.
  - `Png.purs` and `Png.js` read and write PNGs through pngjs, and
    `Timing.purs` and `Timing.js` time the dithering. That's all the
    JavaScript in the package: the screen file is written from PureScript,
    with the `node-fs` package.
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
