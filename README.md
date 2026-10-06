# puregrain

[![CI](https://github.com/roman-mkh/puregrain/actions/workflows/ci.yml/badge.svg)](https://github.com/roman-mkh/puregrain/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/roman-mkh/puregrain)](LICENSE)

Error-diffusion and ordered dithering in PureScript: Floyd–Steinberg,
Atkinson, Jarvis–Judice–Ninke and Bayer, for grayscale and color images,
down to a few gray levels, a few levels per color channel, or a fixed
palette such as CGA or the Commodore 64. It comes with a command-line tool
for PNG images.

> **Status: pre-release.** The library works and is tested. Its public
> interface is being settled: the modules have their final names
> (`Puregrain.*`), but some functions may still change before the first
> release. It isn't published on Pursuit or npm yet.

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

## Getting started

Needs Node.js (developed with v22). From the repository root:

```bash
npm install               # the PureScript compiler, spago, pngjs
npm run build             # compiles the library and the command-line tool
npm test                  # the library's and the tool's test suites
npm run generate-images   # test images in samples/

# dither a test image to 1-bit black and white
npm run dither-cli -- samples/gray-512.png samples/out.png
```

More examples, every option, and how gray and color output are chosen:
[cli/README.md](cli/README.md).

## Repository layout

| Path | What |
|---|---|
| `src/`, `test/` | The library (`Puregrain.*` modules; `Puregrain.Internal.*` are internal) and its tests |
| `cli/` | The command-line tool, a separate package that uses the library |
| `scripts/` | Test-image generator, benchmark, benchmark chart, end-to-end CLI checks |
| `.github/workflows/` | CI: build, tests and end-to-end checks on every push |
| `docs/` | Documentation (below) |

Both packages live in one [spago](https://github.com/purescript/spago)
workspace and are built together.

## Documentation

| Document | Contents |
|---|---|
| [cli/README.md](cli/README.md) | The command-line tool: quick start, options, examples |
| [docs/ordered-dithering.md](docs/ordered-dithering.md) | Ordered (Bayer) dithering: thresholds, the matrices, combining it with error diffusion |
| [docs/palettes.md](docs/palettes.md) | The preset palettes: values, sources, equivalences |
| [docs/test-images.md](docs/test-images.md) | The generated test images, and what to look for in the results |
| [docs/benchmarks-dithering.md](docs/benchmarks-dithering.md) | Current performance, per mode and kernel |
| [docs/benchmarks-fifo.md](docs/benchmarks-fifo.md) | History: how an O(N³) slowdown was found and fixed |
| [CLAUDE.md](CLAUDE.md) | Design decisions and their reasons (kept up to date for the AI assistant used in development) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How work is done: setup, branches, CI, versions, releases |
| [TODO.md](TODO.md) | Open work and ideas |

## License

MIT: use it in any project, open or closed, free or commercial; keep the
copyright and license notice. See [LICENSE](LICENSE).
