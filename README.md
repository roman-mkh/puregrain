# puregrain

[![CI](https://github.com/roman-mkh/puregrain/actions/workflows/ci.yml/badge.svg)](https://github.com/roman-mkh/puregrain/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/roman-mkh/puregrain)](LICENSE)

Error-diffusion and ordered dithering in PureScript: Floyd–Steinberg,
Atkinson, Jarvis–Judice–Ninke and Bayer, for grayscale and color images,
down to a few gray levels, a few levels per color channel, or a fixed
palette such as CGA or the Commodore 64. It comes with a
[command-line tool](cli/README.md) for PNG images.

> **Status: first release (0.x).** The library works and is tested.
> Before 1.0, a breaking change raises the minor version (0.1 → 0.2);
> [CHANGELOG.md](CHANGELOG.md) lists the changes. API reference:
> [Pursuit](https://pursuit.purescript.org/packages/purescript-puregrain).
> Not on npm yet.

## What it does

- **Error diffusion with a choice of kernel:** Floyd–Steinberg, Atkinson,
  Jarvis–Judice–Ninke, or your own (a list of neighbour offsets and
  weights, checked when you build it).
- **Grayscale and color.** For color there are two approaches:
  - dither each channel on its own, e.g. 4 levels per channel;
  - or pick the nearest color from a palette, looking at the whole pixel.
- **Ordered (Bayer) dithering:** Bayer matrices of any power-of-2 size,
  or your own threshold map; on its own, or combined with error diffusion.
  See [docs/ordered-dithering.md](docs/ordered-dithering.md).
- **Ready-made palettes:** black & white, web-safe, CGA/EGA/VGA, ANSI
  16/256 (xterm), Commodore 64, ZX Spectrum. Every palette's values are
  checked against a cited source. See [docs/palettes.md](docs/palettes.md).
- **In memory or as a stream:** dither a whole image at once, or a lazy
  stream of rows, each dithered only when it's needed, so only the rows in
  flight are in memory and the input can even be endless. Or go one row
  at a time from any source, a network stream for example, with your own
  loop.
- **Time grows linearly with the pixel count,** currently about 2 µs per
  pixel for gray Floyd–Steinberg. See
  [docs/benchmarks-dithering.md](docs/benchmarks-dithering.md).

## When to use it, and when not

**Use it when:**

- **You need dithering inside a PureScript program.** Pure functions,
  written entirely in PureScript, with no native dependencies: it runs
  wherever JavaScript runs (Node, browsers).
- **Images are large or streamed.** Rows are dithered one at a time: only
  the rows in flight are in memory, and the source can be a file or a
  network stream.

**Look elsewhere when:**

- **Speed matters.** It runs as plain JavaScript; timings per mode and
  kernel are in [the benchmarks](docs/benchmarks-dithering.md). For batches
  of large images or interactive use, a native tool such as ImageMagick
  is the better choice.
- **You need the best photo quality.** No gamma-correct (linear-light)
  diffusion, no perceptual color distance and no serpentine scanning yet
  (see [Limitations](cli/README.md#limitations)).

## Getting started

### In your PureScript project

```bash
spago install puregrain
```

New packages join the PureScript package sets the day after their release.
If spago doesn't find puregrain, your project uses an older set;
`spago upgrade` moves it to the latest one.

A first program: a small gray gradient, made in code, and the same gradient
dithered to black and white with Floyd–Steinberg, both printed as text.

```purescript
import Puregrain as P

-- | A small gray image: 8 rows of 32 pixels, from black (0.0) on the left
-- | to white (255.0) on the right.
gradient :: Array (Array Number)
gradient = Array.replicate 8 (map (\x -> toNumber x * 255.0 / 31.0) (Array.range 0 31))

main :: Effect Unit
main = do
  log "The original gradient (shown with 5 shades):"
  log (render gradient)
  log ""
  log "Dithered to black and white with Floyd-Steinberg:"
  log (render (P.ditherImage P.floydSteinberg (P.threshold 128.0) gradient))
```

`ditherImage` takes a kernel (where each pixel's rounding error goes), a
quantizer (which values a pixel may take) and the image: an array of rows,
each an array of pixels. Here a pixel is a gray `Number` from 0.0 (black)
to 255.0 (white); for color, it's `P.RGB`. `render` turns an image into
text; the whole program, ready to run, is
[QuickStart.purs](examples/src/Puregrain/Examples/QuickStart.purs). Run it
([examples/](examples/README.md) explains how) and your terminal shows the
gradient twice: in 5 shades of gray, then dithered to just black and white,
as dots whose density follows the gray. The examples also compare more ways
to dither the same gradient, and show how to try your own variations in the
REPL.

The library works on arrays of pixels; reading and writing image files is
up to your application (the command-line tool below does it in Node, with
pngjs).

### The command-line tool

Dithers PNG images, without writing code. It isn't on npm yet; run it from
a checkout of this repository (needs Node.js, developed with v22):

```bash
npm install     # the PureScript compiler, spago, pngjs
npm run build   # compiles the library, the tool and the examples
npm run dither-cli -- photo.png dithered.png --palette c64
```

More examples, every option, and how gray and color output are chosen:
[cli/README.md](cli/README.md).

### Working on this repository

After `npm install` and `npm run build`:

```bash
npm test                  # the library's and the tool's test suites
npm run check             # what CI runs: strict build, tests, end-to-end checks
npm run generate-images   # test images in samples/
```

How work is done (branches, CI, releases): [CONTRIBUTING.md](CONTRIBUTING.md).

## Repository layout

| Path | What |
|---|---|
| `src/`, `test/` | The library (`Puregrain.*` modules; `Puregrain.Internal.*` are internal) and its tests |
| `cli/` | The command-line tool, a separate package that uses the library |
| `examples/` | Small example programs, among them the quick start above; a separate package |
| `scripts/` | Test-image generator, benchmark, benchmark chart, end-to-end CLI checks |
| `.github/workflows/` | CI: build, tests and end-to-end checks on every push |
| `docs/` | Documentation (below) |

The three packages live in one [spago](https://github.com/purescript/spago)
workspace and are built together.

## Documentation

| Document | Contents |
|---|---|
| [examples/README.md](examples/README.md) | The example programs: what each shows, how to run them, the REPL |
| [cli/README.md](cli/README.md) | The command-line tool: quick start, options, examples |
| [docs/ordered-dithering.md](docs/ordered-dithering.md) | Ordered (Bayer) dithering: thresholds, the matrices, combining it with error diffusion |
| [docs/palettes.md](docs/palettes.md) | The preset palettes: values, sources, equivalences |
| [docs/test-images.md](docs/test-images.md) | The generated test images, and what to look for in the results |
| [docs/benchmarks-dithering.md](docs/benchmarks-dithering.md) | Current performance, per mode and kernel |
| [docs/benchmarks-fifo.md](docs/benchmarks-fifo.md) | History: how an O(N³) slowdown was found and fixed |
| [CLAUDE.md](CLAUDE.md) | Design decisions and their reasons (kept up to date for the AI assistant used in development) |
| [CHANGELOG.md](CHANGELOG.md) | Changes to the library, per version |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How work is done: setup, branches, CI, versions, releases |
| [TODO.md](TODO.md) | Open work and ideas |

## License

MIT: use it in any project, open or closed, free or commercial; keep the
copyright and license notice. See [LICENSE](LICENSE).
