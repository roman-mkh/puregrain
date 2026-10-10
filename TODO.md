# TODO / Future Improvements

Open work, roughly in order. The reasons behind past decisions are in
`CLAUDE.md`.

## Public interface (v0.1)

- [ ] **Release v0.1:** follow CONTRIBUTING.md, "Releases" (the tools are ready: version ranges,
      `npm run release:check`, CI on tags).
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
      from 512² to 1024² in the `CatQueue` run. One mode is enough. A real photo shows it keeps growing:
      6000 × 5807 (34.8 MP, gray Floyd-Steinberg, on mains, 2026-10-09) took 270 s, 7.75 µs per pixel, 4× the
      1024² rate (linear would be 68 s). Suspects, not measured yet:
      - the heap size: the CLI holds all rows twice as JS arrays (gray input and output, through
        `ditherImage`), which the garbage collector has to manage;
      - the row width: each row's error queues hold one boxed entry per pixel until the next row consumes
        them; at 6000 pixels they may outlive V8's young generation and get promoted to the old one, where
        collecting is expensive (and cache misses grow with the width too).

      Experiments: 2048² and 4096²; the same pixel count wide and tall (6000 × 700 against 700 × 6000);
      one run with `node --max-semi-space-size=128` (a larger young generation). They decide between
      streaming in the CLI (see "Command-line tool") and fewer allocations per pixel in the library.
- [ ] **`nearestLevel` binary search** instead of the linear scan (see its `TODO(benchmark)` note). Low
      priority: `--levels 4` costs ×1.13 of a threshold (2026-10-04).

## Command-line tool

- [ ] **Streaming rows, with a progress indicator:** use `ditherRows` or the stepper instead of
      `ditherImage`, so the JS heap holds a few rows instead of the whole image (pngjs still decodes the file
      into one buffer, but buffers live outside the JS heap), and print progress every few percent to stderr
      (the benchmark only looks for the "Dithered in … ms" line). Whether this also fixes the slowdown on
      large images depends on the scaling experiments (see "Performance").
- [ ] **Compact PNG output:** 1-bit PNGs for black and white, and indexed PNGs (color type 3, 1–8 bits)
      for palettes; today every output has 8 bits per channel. Measured 2026-10-09: the same black-and-white
      image as a 1-bit PNG is half the size (2.66 → 1.33 MB for a 6000 × 5807 photo, 46% for the 512² gray
      composite). pngjs can write neither (only 8- or 16-bit samples, no color type 3), so it needs a small
      writer of our own on Node's `zlib`: about 40 lines for 1-bit, tried in a scratch script.

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
