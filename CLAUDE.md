# puregrain — project memory

A PureScript library for dithering (Floyd–Steinberg, Atkinson, JJN, ...),
targeting eventual publication on Pursuit + an npm wrapper. This file
captures architectural decisions and rationale from the design
conversation that built this codebase, since a lot of it isn't visible
from the code alone.

@docs/benchmarks-dithering.md
@TODO.md

## Workspace layout (spago monorepo)

- **`puregrain`** (root `spago.yaml`, `src/`, `test/`) — the library.
  Its dependencies are what every Pursuit user inherits, so they must
  stay exact: keep `spago build --pedantic-packages` clean, keep
  test-only packages under `test.dependencies`, and never add
  Node-only or app packages here.
- **`puregrain-cli`** (`cli/spago.yaml`, `cli/src/`, modules
  `Puregrain.Cli.*`) — the command-line tool, a separate package that
  depends on the library. The only JS in it is the pngjs wrapper
  (`Puregrain.Cli.Png`). Run through `npm run dither-cli -- ...`: the
  launcher `cli/bin/puregrain-cli.mjs` runs the compiled output
  directly, with no rebuild per run (benchmark timings rely on this).
  `npm run check:cli` runs its end-to-end exact checks. User docs:
  `cli/README.md` (quick start, options, modes, examples). Keep
  `Puregrain.Cli.Main` I/O-only: decisions go in `Puregrain.Cli.Pipeline`
  (pure, tested in `cli/test/`). Kernel/palette CLI names are defined
  once (`kernelName`/`paletteName`); tables and help text derive from
  them. `spago test` runs both packages' suites (library, then CLI).
- Module names must be unique across all packages in the workspace
  (shared `output/`) — hence no `Main` modules; entry points get
  qualified names like `Puregrain.Cli.Main`.
- The future web GUI would be another sibling package. Splitting
  packages into separate repos is possible later; the package
  boundary is what matters.

## Documentation map

- `README.md` — lean entry point by decision: what it is, status,
  features (each linking to its doc), layout, getting started, doc
  index. No API usage examples until the public-interface step (the
  `Dither.*` → `Puregrain.*` rename would invalidate them).
- Reference docs live in `docs/` and are the single source of truth:
  `palettes.md`, `test-images.md`, `benchmarks-dithering.md` (current),
  `benchmarks-fifo.md` (finished record). READMEs summarize and link
  rather than copy, so tables don't drift apart.
- `cli/README.md` — the CLI's user docs.

## Core architecture

- `Dither.Kernel` — a `Kernel` is `Array Offset` (`{dx, dy, weight}`),
  user-facing and simple. `CompiledKernel` (record: `currentOffsets`,
  `futureLayers`, `maxDepth`) is a precomputed cache built once via
  `compileKernel`, threaded through the hot path instead of recomputing
  `Array.filter`s per pixel (PureScript does NOT auto-memoize like GHC
  sometimes does — this bit us once as a real, measured regression).
- `Dither.Fifo` — `class Fifo (f :: Type -> Type)` with 4 methods:
  `replicate`, `enqueue`, `dequeue`, `replace` (shift-left-by-n +
  zero-fill, its own method rather than `drop`+`<>` because that
  composition is O(n) even when n is small — see below). Instances:
  `List.Lazy`, `Data.List` (strict), `Array`, `Data.Sequence.Seq`.
  **`Seq` is the production default** (see Performance below).
- `Dither.Pixel` — `Gray = Number`; `RGB`/`RGBA` are `newtype`s (not
  `type` aliases — aliases sharing record shape would collide on
  instance resolution) with hand-written `Semiring`/`Ring` (honest
  `mul`/`one`, unused by diffusion but a legitimate algebra) and a
  custom `class Ring a <= Scalable a where scale :: Number -> a -> a`
  (kernel weights are always `Number` regardless of channel count).
  `newtype Quantize a = Quantize (Context -> a -> a)` with
  `type Context = { x :: Int, y :: Int }` (the pixel's position, for
  Bayer/noise later). Position-blind quantizers are built with
  `quantize :: (a -> a) -> Quantize a`; helpers needing only some
  context fields take `forall r. { x :: Int | r }` (row polymorphism —
  PureScript's answer to Haskell's `HasX` classes), so `Context` can
  grow without breaking them. No Reader monad: a plain function of a
  record, by decision. The scalarED toolkit lives
  here too: `class MapChannels` (+ `Number`/`RGB`/`RGBA` instances),
  `perChannel`, `nearestLevel`, `evenRamp`, `threshold` (see
  scalarED/vectorED below).
- `Dither.Palette` — vectorED: `CompiledPalette` (a `NonEmptyArray RGB`
  packed with a swappable distance metric, currently only `distance2`),
  `nearestColorFast`/`nearestColor`. Note `distance2` is plain RGB
  distance, not perceptual: pure green is nearer to black than to white
  (pinned by a test).
- `Dither.Palette.Presets` — fixed palettes as plain `NonEmptyArray RGB`
  (the caller picks the metric): `blackWhite`, `websafe216`, `cga16`
  (= EGA/VGA default; the Linux console's values, in ANSI order —
  verified in the kernel's vt.c; Wikipedia's terminal table has a
  display-adjusted "CGA/EGA/VGA" column, not these digital values),
  `ansi16`/`ansi256` (xterm's values — plain presets, deliberately no
  terminal-scheme parameter: the console/VGA colors are already
  `cga16`), `c64` (Pepto), `zxSpectrum`
  (normal = 0xD8). Historical/terminal palettes have no official RGB, so
  every preset cites its source in a comment — values were checked
  against those sources, not recalled. Per-pixel only; block-constrained
  looks (ZX 8×8 attribute cells, pseudo-graphics) are a TODO.md item.
  User-facing reference: `docs/palettes.md` — keep it in step with the
  module (a new preset means a new row there and in cli/README.md's
  short table).
- No JS-facing layer exists right now, by decision: the old
  `Dither.Ffi` (a monomorphic `ditherImageArray` wrapper) was deleted
  once the JS CLI, its only user, was replaced by `puregrain-cli`. The
  npm interface gets designed fresh when the npm package work starts
  — JS can't call typeclass-polymorphic functions (they need instance
  dictionaries), so it will again be a monomorphic layer.
- `Dither.State` / `Dither.Step` / `Dither.Row` / `Dither.Image` —
  diffusion core, polymorphic over `Fifo f` and `Ring a, Scalable a`.
  `RowLayer f a = Array (f a)`, `DelayLine f a = Array (RowLayer f a)`.
  `current`/`matured`/`building` are row-local (`RowState`); only
  `delayLines` and the row counter `nextRow` cross row boundaries
  (`DitherState`). Positions: `y` is `DitherState.nextRow` (a caller
  stepping rows can't pass a wrong one); `x`/`y` ride in `RowState`, which `step` rebuilds per pixel
  anyway. Not `mapAccumLWithIndex`: on Array it's a generic default
  (`sequence <<< mapWithIndex`, an extra pass per row), while
  `mapAccumL` uses the native `traverse`.

## Key design decisions (with rationale)

- **Multi-channel model: scalarED vs. vectorED.** Two ways to dither a
  multi-channel pixel, distinguished *only* by how the quantizer is
  built — both are an ordinary `Quantize a` fed to the same, unmodified
  `ditherImage`; there is no separate pipeline per mode.
  - **scalarED** — each channel is an independent copy of the same
    scalar algorithm. Write a `Quantize Number` (e.g. `nearestLevel
    (evenRamp 4)`) and lift it with `perChannel` (via `class
    MapChannels`). The `Number -> Number` type is the guarantee: it
    only ever sees one channel's value, so it *cannot* couple channels
    — by construction, not by convention. Because `RGB`/`RGBA`'s
    `Ring`/`Scalable` instances are component-wise, one pass over an
    RGB image gives exactly what three separate grayscale passes over
    the channel planes would (property-tested in
    `Test.Dither.PixelSpec`).
  - **vectorED** — the quantizer sees the whole pixel at once, e.g.
    `Dither.Palette.nearestColor` (nearest palette color by a distance
    metric). Write the `Quantize a` directly on the composite type.
  - Channel *count* never changes mid-pipeline — reconsidered and kept
    (2026-09-23): a `Quantize a b` was rejected because `outErr =
    corrected - quantized` must stay in `a`'s `Ring` (the error has to
    live in the space future pixels are added in). Output-format
    reduction (e.g. RGB→Gray) is a plain post-hoc `map` over
    `ditherImage`'s result; image-dependent palette generation (e.g.
    median-cut) happens *outside* this library (FFI/caller side).
    Fixed preset palettes (e.g. `websafe216`) live inside it.
- **`DelayLine` is pre-padded to length `dy`, not grown from empty**:
  `initState` builds each `DelayLine` as `Array.replicate dy []` —
  already at its full, constant length `dy`, from the very first row
  (it has to be: `extractMatured`'s `Array.uncons` would crash on a
  truly empty `DelayLine`). What ramps up over the first `dy` rows is
  *content*, not length: each row pops one slot off the front
  (placeholder or real) and pushes one freshly-computed real layer
  onto the back, so it takes exactly `dy` rows for all `dy` original
  placeholders to be flushed out — the array's length never changes.
  An *empty* `RowLayer` (`[]`, a placeholder slot with zero fifos)
  contributes zero error for free, since `sumErrors [] = 0.0` — no
  placeholder/sentinel type needed. (We tried a `Constant | Real`
  sum-type wrapper for this first — real, measured per-pixel overhead
  from the extra allocation/unwrap; abandoned in favor of this.)
- **`replace` is a first-class `Fifo` method**, not `drop` + `<>`,
  because that composition is O(n) regardless of how small the drop
  count is (the `<>` walks the whole kept prefix). A finger-tree-backed
  instance (`Seq`) can implement `replace` via cheap concatenation
  (O(log n)) instead.
- **`ST` doesn't fit the `Fifo` abstraction**: `enqueue`/`dequeue` are
  called from separate call sites across a value's lifetime (not one
  `runST` block), so real `O(1)` mutation there would require either
  unsafe linear-use assumptions or a hand-rolled consumed-flag +
  defensive-copy scheme — both rejected as not worth it given `Seq`
  already achieves the target asymptotic complexity. A genuinely
  mutation-based backend would need a different algorithm shape (one
  `runST` block per row/image), not a `Fifo` instance.

## Performance (history + charts: `docs/benchmarks-fifo.md`; current baseline: `docs/benchmarks-dithering.md`)

Root cause found and fixed: `Data.List.Lazy`'s `snoc` is O(n), so
accumulating a row's worth of diffused error (`building`, up to
`width` `enqueue` calls) cost O(width²) per row → O(width³) total for
square images — confirmed empirically (growth ratio → 8× per side-
doubling) before the fix, → 4× (i.e. `O(width×height)`, optimal) after
switching the default `Fifo` backend to `Seq`. ~38× speedup at
1024×1024. `Array` was benchmarked too (native memcpy-speed constants
beat asymptotics at tested sizes, ≤1024) — worth re-testing at larger
N since its growth-ratio trend was climbing back toward cubic.

## Testing

`Test.Dither.Reference` — an independent, deliberately naive
`ST`-based two-loop reference implementation (no `Fifo`/padding
machinery), used as a QuickCheck oracle. `Test.Dither.Arbitrary`
generates random `Kernel`s and images. `Test.Dither.DiffusionMechanicsSpec`
checks every `Fifo` backend against the reference on random inputs —
this is what actually caught real bugs (see Gotchas below), where
hand-picked example kernels (Floyd–Steinberg, Atkinson, JJN — all
`maxDepth ≥ 1`) did not.

The documented exact checks (docs/test-images.md → "Exact checks") are
deliberately tested twice, at two levels: as Spec properties over
arbitrary kernels/palettes/images ("whole images" blocks in
`PaletteSpec`/`PixelSpec`), and end to end through the real CLI on the
generated images (`npm run check:cli`). Not redundant: Spec can't
reach the CLI's plumbing (PNG I/O, gray/RGB routing, launcher);
check:cli can't cover arbitrary inputs.

Visual checks and benchmarks share one set of generated images:
`scripts/generate-images.mjs` (drawing code only in
`scripts/lib/test-patterns.mjs`), documented tile by tile in
`docs/test-images.md`. Generated images go to gitignored `samples/`;
the two doc previews in `docs/images/test-images/` are the only ones
committed (refresh: `npm run docs:images`). pngjs gotcha: the output
PNG color type must be passed to `PNG.sync.write(png, { colorType })`
— the `new PNG({ colorType })` constructor option is ignored by the
sync writer, which silently wrote every "grayscale" image as RGBA.

## PureScript gotchas hit during development (worth remembering)

- **`(..)` is NOT empty when reversed**: `1 .. 0` evaluates to `[1, 0]`
  (descending), NOT `[]` like Haskell's `[1..0]`. This caused a real,
  QuickCheck-caught bug whenever `maxDepth == 0` (a legitimately valid
  kernel with no cross-row diffusion). Fixed via `Dither.Util.safeRange`
  — use it, not raw `(..)`, anywhere the upper bound can legitimately
  be less than the lower bound.
- **No automatic memoization**: unlike GHC, PureScript never shares
  repeated pure computations for you. If something is computed inside
  a per-pixel hot path but doesn't depend on the pixel, hoist it out
  explicitly (see `CompiledKernel`).
- Several library API guesses were WRONG during development
  (`Data.List.replicate`, `chooseFloat` vs `choose`, etc.) — when
  unsure of an exact current signature, check rather than assume;
  this project's history has repeated real mismatches between assumed
  and actual APIs.

## Working style established in this project

- Go slow, one architectural change at a time; confirm before moving
  to the next step on anything non-trivial.
- Don't add generality/abstraction ahead of a concrete, current need
  (YAGNI was invoked repeatedly and correctly) — e.g. `Pixel`
  generalization was deliberately deferred until color dithering was
  the actual next task, not done speculatively earlier.
- Benchmark before optimizing, and document benchmark results with a
  reproducible method + chart, including negative/regression results,
  not just wins. New runs go in `docs/benchmarks-dithering.md` as a
  new dated section (`npm run bench`, chart via
  `scripts/plot-benchmarks.mjs`); `docs/benchmarks-fifo.md` is the
  finished record of the `Fifo` investigation and isn't extended.
