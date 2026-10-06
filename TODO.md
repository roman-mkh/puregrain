# TODO / Future Improvements

Open work, roughly in order. The reasons behind past decisions are in
`CLAUDE.md`; the "Done" list at the end is a short-lived record, dropped at
the v0.1 release.

## Public interface (v0.1)

- [ ] **Public row-by-row stepper: reusing an old state.** `Fifo CatQueue` is O(1) amortized only if each
      queue version is used once. A reused old one repeats the list reversal it already did: still correct,
      just slower. Inside the library every state is used once, but a public stepper would let callers keep a
      state and run from it again (e.g. undo in the web demo). Its API docs must state "use each state once",
      or the design must handle reuse otherwise. See the `CatQueue` instance in `Puregrain.Internal.Fifo` and
      the `DitherState` doc comment in `Puregrain.Internal.State`.
      Also: a row of a different length is a runtime error today (`unsafeCrashWith` in `ditherRow`, by
      decision, since `ditherImage`'s lazy list has no error channel). A stepper fed one row at a time could
      return `Either String (Tuple state row)` instead, so the caller can react; `ditherImage` would then turn
      a `Left` into the same runtime error.
      The stepper's design also decides whether the kernel and the quantizer travel together as one
      configuration record held inside the opaque state (the early `DitherAlgo` idea).
- [ ] **Public image type.** Keep `ditherImage` on the lazy `List (Array a)`, for streaming. Consider an
      in-memory convenience on `Array (Array a)` next to it (e.g. `ditherArray`): the CLI
      (`Puregrain.Cli.Main.dither`) and the tests (`Test.Puregrain.Util.dither`) each carry the same
      `LL.toUnfoldable (ditherImage k q (LL.fromFoldable rows))` helper today. No type aliases for rows or
      images (decided 2026-10-04, replacing the old "alias `Array Number` to PixelRow" entry): a `type` adds
      no safety, hides the laziness behind a lookup, and `Row`/`Image` clash with PureScript's `Row` kind
      and with common names in users' code. If a name is ever wanted after all: `Scanline a`.
      Folded in, meaning to be recalled: the older note "ditherImage: LL.List - maybe define custom impl
      here (diff to typeclass Fifo)".
- [ ] **Release v0.1:** version ranges for the dependencies (`spago build --ensure-ranges`); a
      `release.yml` workflow; publish to the registry and Pursuit; drop the "Done" list from this file.

## Performance

Measured 2026-10-04 (`docs/benchmarks-dithering.md`): Floyd–Steinberg with a threshold takes 1.9 µs per
pixel, of which about 1.3 µs is the diffusion (without it, 0.63 µs).

- [ ] **RGB arithmetic:** `--levels 6` takes ×2.3 of a gray threshold, and even `--palette bw` ×1.9. Look at
      how `RGB` values are added and scaled per pixel (each operation allocates a new record).
- [ ] **Palette search** (`nearestColorFast`): websafe216 takes ×2.1–2.3 of `--levels 6`, for the same output.
- [ ] **ST-based diffusion:** a ring buffer in mutable arrays, compared with the `Fifo` queues. It needs one
      `runST` per row or per image, a different shape from the `Fifo` class (see CLAUDE.md, "`ST` doesn't fit
      the `Fifo` abstraction").
- [ ] **Scaling at 2048² and 4096²** (still open from `docs/benchmarks-fifo.md`): time per pixel rose 12–31%
      from 512² to 1024² in the `CatQueue` run. One mode is enough.
- [ ] **`nearestLevel` binary search** instead of the linear scan (see its `TODO(benchmark)` note). Low
      priority: `--levels 4` costs ×1.13 of a threshold (2026-10-04).

## Algorithms

- [ ] **White-noise (random) dithering:** thresholds from a seeded hash of the pixel's position, a `Quantize`
      over `Context` with no state, combinable with any kernel like `Puregrain.Ordered`. Needs a seed (closed
      over by the quantizer, or in `Context`) and a deterministic hash. Blue noise is already covered: a
      blue-noise mask is a custom threshold map (`Puregrain.Ordered.compileThresholdMap`).
- [ ] **Ostromoukhov's variable error diffusion:** the kernel's weights depend on the pixel's input value.
      The step uses fixed weights per kernel today, so this needs per-pixel weights in `Puregrain.Internal.Step`.
- [ ] **Serpentine scanning:** alternate the scan direction row by row, mirroring the kernel on right-to-left
      rows, to reduce directional artifacts (cli/README.md, "Limitations").
- [ ] **Dithering in linear light:** today error is diffused on the stored, gamma-encoded sRGB values, which
      skews mid-tones slightly; convert to linear light first (cli/README.md, "Limitations": "fixing this is
      planned").

## Application

- [ ] **Browser demo:** compare all the dithering variants visually, with the Canvas API through FFI
      (purescript-canvas). A sibling package in the workspace, after the public API; built on the row-by-row
      stepper, in a Web Worker so the page stays responsive.
- [ ] **npm package:** a monomorphic JS layer (JavaScript can't call class-polymorphic functions), a bundle,
      and `.d.ts` types.
- [ ] **Quality metrics** (PSNR/SSIM) to compare the algorithms.

## Future directions (not in scope now)

- [ ] CMY/CMYK pixel types + GCR/UCR (gray component replacement / under
      color removal). Algebraically CMY(K) is identical to RGB(A) — same
      independent-`Ring`-channel shape, same `Scalable` — so the type
      itself is cheap to add later (a straightforward newtype + instances,
      same as RGB/RGBA, no new abstraction needed). The real work is GCR/
      UCR: deriving K from C/M/Y is a color-management step that has to
      happen *before* dithering, not something plain independent-channel
      error diffusion gives you — naive 4-independent-channel diffusion is
      representable in this architecture today but isn't real print-
      quality CMYK output on its own (no per-channel screen angles, no
      moiré avoidance). Needs a concrete print/halftone target to justify.
- [ ] Block-constrained output — a different kind of algorithm, out of scope for now. The real ZX Spectrum look
      (2 colors per 8×8 cell), C64 multicolor modes, and pseudo-graphics (ANSI/Unicode block characters,
      PETSCII, teletext mosaics) all restrict each *cell* rather than each pixel. The per-pixel `Quantize`
      can't see a cell, so it needs a cell step first — choose each cell's colors (or its character plus
      foreground/background), then dither inside the cell with that small palette (reusable:
      `nearestColor` on a 2-color palette). The per-pixel presets (`zxSpectrum`, `c64`) exist today.
- [ ] Ordered dithering against a palette (vectorED) — not supported: `Puregrain.Ordered` decides between two
      neighbouring levels per channel, and a palette's colors have no such order. Needs a different method,
      e.g. Joel Yliluoma's positional dithering algorithms. Until then, palettes that are a grid of per-channel
      levels work through `--levels` (`--levels 6` = web-safe). See docs/ordered-dithering.md, "Not supported".
- [ ] `distance2Lab` — CIELAB-space distance metric for `Puregrain.Palette`,
      as a second argument to plug into `compilePalette`/
      `compilePaletteFromArray` alongside `distance2` (that's exactly what
      `CompiledPalette` packing the distance function was designed to make
      swappable — see `Puregrain.Palette`). Requires an RGB→Lab conversion
      (through XYZ, with a chosen white point/gamma assumption) that
      doesn't exist yet anywhere in this codebase.
- [ ] Effectful quantizers and row sources (pipes/coroutines): postponed until someone needs them. Quantizers
      stay pure; if ever, as an extension package.

## Done (record; dropped at the v0.1 release)

- 2026-10-05 — API decisions: the `Fifo` class (with `ditherImageWith`) stays internal; `Quantize` is opaque,
  built by `quantize` (position-blind) or the new `quantizeWith` (uses the position), run by `runQuantize`.
- 2026-10-05 — Repository public, after rewriting the history so every commit carries the GitHub no-reply
  address instead of a private one.

- 2026-10-05 — CI: `.github/workflows/ci.yml` runs the build (`--pedantic-packages --strict`), both test
  suites and `check:cli` on every push and pull request to `master`, as a clean build; badge in README.md;
  `npm run check` runs the same locally. First run green in about a minute.

- 2026-10-04 — License: MIT (`LICENSE`, covering the library and the CLI), declared in `spago.yaml`
  (`package.publish`, with the planned version 0.1.0) and `package.json`.

- 2026-10-03 — Publishing unblocked: `Seq` (a git fork of `sequences`) replaced by `Data.CatQueue` from the
  registry package `catenable-lists`; also ~3.6× faster (`docs/benchmarks-dithering.md`).
- `Data.Sequence`-based `Fifo` instead of the lazy list: the O(N³) fix (`docs/benchmarks-fifo.md`).
- 2026-10-03 — Custom user data for quantizers: a quantizer is a closure; with `Context` it can also look up
  per-pixel data, such as a mask, by position.
- 2026-10-03 — Quantizers know the pixel's position (`Context { x, y }`; `x == 0` is the row start). State
  carried over from earlier pixels deliberately isn't offered: quantizers stay pure.
- Tests: moved from `Test.Assert` to purescript-spec (structured output, selective runs) and QuickCheck.
  Every `Fifo` backend is checked against an independent ST-based reference (`DiffusionMechanicsSpec`);
  `Test.Dither.Row`/`Step` migrated to specs; the legacy `Image`/`Playground` modules deleted (2026-10-04).
- Test generators (`Test.Puregrain.Arbitrary`): images of various sizes; kernels of distinct forward
  offsets, always accepted by `fromOffsets`, with weights random in [0, 1].
- One generator for visual-check and benchmark images (`scripts/generate-images.mjs`), and benchmark
  automation (`npm run bench`).
- Closed without doing (2026-10-04):
  - a version of `ditherRow`/`ditherImage` polymorphic over `Traversable f`: rows stay `Array a` (see
    "Public image type"), and no use needs another container;
  - a typeclass + Reader monad to pass the algorithm configuration: decided against, plain values
    (CLAUDE.md);
  - a determinism property for constant input: every function involved is pure, so it holds trivially;
    flat-image exact checks exist (`OrderedSpec`, `PixelSpec`);
  - `normalizeKernel`/`fillGaps` (pad each row of offsets to one shape with zero weights): compilation
    groups offsets by `dy`, and an empty layer costs nothing (`[]` contributes zero), proven on kernels with
    gaps by `DiffusionMechanicsSpec`; zero-weight padding would only add queue work.
