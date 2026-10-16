# Changelog

All notable changes to the `puregrain` library. Versions follow
[semantic versioning](https://semver.org); before 1.0, a breaking change
raises the minor version (0.1 → 0.2).

## Unreleased

### Added

- `Puregrain.Cells`: dithering with cells, as on 8-bit home computers. Each
  cell of `width × height` pixels may use only one or two colors, chosen
  per cell from a list of candidates. A `CellMode` holds the cell size
  and the candidates with their colors. `ditherCells` dithers an image in
  memory; `ditherBands` a lazy stream of rows, one row of cells at a time.
  Both return the chosen candidates with the dithered rows. Inside the
  cells, pixels get error diffusion (`nearestInCell`) or ordered
  dithering with any threshold map (`orderedInCell`), on its own or
  combined with a kernel.
- `Puregrain.Machine.ZxSpectrum`: the ZX Spectrum's screen for
  `Puregrain.Cells`: 8 × 8 cells, each with an ink and a paper color and
  one BRIGHT bit (`attributes`, the 71 cell palettes that look different;
  `attributePalette`; `screen`, the screen mode). `toScr` writes a dithered 256 × 192
  screen as a `.scr` file, the Spectrum's own screen format, which
  emulators open.

## 0.1.0 - 2026-10-10

The first release.

### Added

- Error diffusion for gray (`Number`), `RGB` and `RGBA` pixels, in three
  ways that give the same rows: `ditherImage` (an image in memory),
  `ditherRows` (a lazy stream of rows) and a row-by-row stepper,
  `initDithering` and `ditherRow`, for rows that come from effects.
- Kernels: Floyd–Steinberg, Atkinson, Jarvis–Judice–Ninke, `noDiffusion`,
  and custom kernels checked by `fromOffsets`.
- Quantizers: `threshold`, `nearestLevel` with `evenRamp`, lifted to color
  by `perChannel`; custom ones, which may use the pixel's position,
  through `quantize` and `quantizeWith`.
- Palettes: nearest-color matching (`nearestColor`) with presets
  black-and-white, web-safe 216, CGA 16, ANSI 16 and 256, C64 and
  ZX Spectrum.
- Ordered dithering: Bayer maps of any power-of-2 side and custom threshold
  maps (blue-noise masks, for example), without diffusion or combined with
  any kernel.
- The `Puregrain` module re-exports what a typical application needs.
