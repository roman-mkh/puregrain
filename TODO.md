# TODO / Future Improvements

Open work, roughly in order. The reasons behind past decisions are in
`CLAUDE.md`; the "Done" list at the end is a short-lived record, dropped at
the v0.1 release.

## Public interface (v0.1)

- [ ] **Release v0.1:** follow CONTRIBUTING.md, "Releases" (the tools are ready: version ranges,
      `npm run release:check`, CI on tags); drop the "Done" list from this file in the release commit.
- [ ] **After the first publish:** a Pursuit badge in README.md
      (`https://pursuit.purescript.org/packages/purescript-puregrain/badge`), and the Pursuit link as the
      repo's "Website".

## Performance

Measured 2026-10-04 (`docs/benchmarks-dithering.md`): Floyd–Steinberg with a threshold takes 1.9 µs per
pixel, of which about 1.3 µs is the diffusion (without it, 0.63 µs).

- [ ] **Evaluate purs-backend-es** (a PureScript-aware optimizing backend) for the CLI and the npm bundle:
      an A/B benchmark in one session, byte-identical outputs. The first performance step after v0.1; its
      result decides the items below. (It doesn't affect the library on Pursuit, which ships source.)
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
- [ ] **Riemersma dithering** (an idea): the error travels along a Hilbert curve, a path that fills the image
      in nested U-shapes, and each pixel gets the last ~16 visited pixels' errors with exponentially falling
      weights. Not a kernel, but a different traversal: the whole image in memory (no streaming or stepper),
      so a separate function next to `ditherImage`. The quantizers carry over (`Context` has the position).
      Avoids scan-line "worm" artifacts, but looks grainier; ImageMagick offers it.
- [ ] **Dithering in linear light:** today error is diffused on the stored, gamma-encoded sRGB values, which
      skews mid-tones slightly; convert to linear light first (cli/README.md, "Limitations": "fixing this is
      planned").

## Application

- [ ] **Browser demo:** compare all the dithering variants visually, with the Canvas API through FFI
      (purescript-canvas). A sibling package in the workspace, after the public API; built on the row-by-row
      stepper, in a Web Worker so the page stays responsive.
- [ ] **npm package:** a monomorphic JS layer (JavaScript can't call class-polymorphic functions), a bundle,
      and `.d.ts` types.
      The CLI ships through npm too, not the PureScript registry (spago can't install pngjs): one JS file
      bundled with esbuild, pngjs as an npm dependency, a `bin` entry, so `npx puregrain …` works. It could
      come before the library's JS layer; decide after v0.1, together with the purs-backend-es evaluation.
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
      stay pure; if ever, as an extension package. For row sources, a generic driver on top of the stepper
      would do, e.g. `ditherWith :: forall m a. MonadRec m => … -> m (Maybe (Array a)) -> (Array a -> m Unit)
      -> m Unit` (read rows with an action, pass results to a callback, in `Effect`, `Aff` or any monad that
      supports long loops). Start closed: only for a real use case.
- [ ] MCP server (dithering as a tool for AI assistants): a learning project, not expected to find many
      users. Agents with a shell can already run the CLI (`npx puregrain …` once it's on npm), so for them
      a good CLI matters more (clear `--help`, precise errors, meaningful exit codes). It would serve chat
      apps without a shell. Needs the npm package first: an MCP server is TypeScript/JS on top of its JS layer.

## Done (record; dropped at the v0.1 release)

- 2026-10-07 — Public row-by-row stepper: `initDithering kernel quantize` builds an opaque `Dithering a`
  (compiled kernel, quantizer and state inside: the early `DitherAlgo` idea, settled without a public
  configuration record), and `ditherRow` dithers one row, returning `Either String { row, next }`. A pure
  state machine: the caller runs the loop, so rows produced by effects (a network stream, a file read piece
  by piece) work, and nothing is cached. A row of a different length gives `Left` and leaves the state
  usable; `ditherImage` and `ditherRows` turn the same message into a runtime error. States are freely
  reusable (an undo): stepping from an old state redoes that row's work, the queue reversals included, and
  no more, so the earlier "use each state once" worry was unfounded at the row level.

- 2026-10-07 — Release tooling: `CHANGELOG.md` (Keep a Changelog style, library only); version ranges for
  the library's dependencies (`--ensure-ranges`, from package set 81.3.0 up to the next major);
  `scripts/release-check.mjs` (`npm run release:check -- X.Y.Z`, checks A–F); CI on `v*` tags runs the checks
  and creates the GitHub Release. No separate `release.yml`: `spago publish` pushes the tag itself, right
  before calling the registry, so a tag workflow can't stop a publish; the checks run locally first.
- 2026-10-07 — Publish location in `spago.yaml` (`package.publish.location`: GitHub `roman-mkh/puregrain`),
  which the registry needs to find the source and Pursuit links to.

- 2026-10-06 — Public image type: `ditherImage` takes and returns `Array (Array a)` (in memory, strict),
  `ditherRows` a lazy `List (Array a)` (streaming: each row read and dithered when asked for). Two thin
  drivers over one row function (now `stepRow`), pinned equal by a property; the CLI and test helpers that converted between
  the two are gone. No type aliases for rows or images: a `type` adds no safety, hides the laziness, and
  `Row`/`Image` clash with PureScript's `Row` kind and users' names (`Scanline a` if ever wanted). Closed
  with it, the old note "ditherImage: LL.List - maybe define custom impl here (diff to typeclass Fifo)": we
  stick with `Data.List.Lazy` for pure streaming. A custom pure iterator would have the same power without
  the library functions around it, and `Data.Lazy` is one deferred value, not a stream; effectful sources
  belong to the stepper.

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
  - a version of `ditherRow`/`ditherImage` polymorphic over `Traversable f`: rows stay `Array a` (the
    public image type, 2026-10-06), and no use needs another container;
  - a typeclass + Reader monad to pass the algorithm configuration: decided against, plain values
    (CLAUDE.md);
  - a determinism property for constant input: every function involved is pure, so it holds trivially;
    flat-image exact checks exist (`OrderedSpec`, `PixelSpec`);
  - `normalizeKernel`/`fillGaps` (pad each row of offsets to one shape with zero weights): compilation
    groups offsets by `dy`, and an empty layer costs nothing (`[]` contributes zero), proven on kernels with
    gaps by `DiffusionMechanicsSpec`; zero-weight padding would only add queue work.
