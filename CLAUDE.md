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
  Node-only or app packages here. MIT-licensed (`LICENSE` at the root
  covers the library and the CLI); `package.publish` in `spago.yaml`
  holds the license and the planned version (0.1.0), and
  `package.json` says `"license": "MIT"` too.
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
  them. `--kernel none` is the empty kernel. `--bayer N` (2–16) is its own
  option; how it combines with the quantizer options (only with
  `--levels`; `--palette` is rejected) is checked after optparse, in
  `Options.resolve`, whose rejections `parseOptions` turns into ordinary
  optparse failures (same usage text, exit code 1) — optparse's
  alternatives commit to the first matching option, so the rule can't be
  an alternative without defining `--levels` twice. `spago test` runs
  both packages' suites (library, then CLI).
- Module names must be unique across all packages in the workspace
  (shared `output/`) — hence no `Main` modules; entry points get
  qualified names like `Puregrain.Cli.Main`.
- The future web GUI would be another sibling package. Splitting
  packages into separate repos is possible later; the package
  boundary is what matters.

## Documentation map

- `CONTRIBUTING.md` — the workflow rules (setup, branches, CI,
  versions, release checklist).
- `README.md` — lean entry point by decision: what it is, status,
  features (each linking to its doc), layout, getting started, doc
  index. No API usage examples until the API decisions are settled
  (kernel validation etc.); until then the one canonical example is in
  the `Puregrain` facade's module doc.
- Reference docs live in `docs/` and are the single source of truth:
  `ordered-dithering.md`, `palettes.md`, `test-images.md`,
  `benchmarks-dithering.md` (current),
  `benchmarks-fifo.md` (finished record). READMEs summarize and link
  rather than copy, so tables don't drift apart.
- `cli/README.md` — the CLI's user docs.

## Core architecture

- **Module structure (reshape of 2026-10-04, `Dither.*` → `Puregrain.*`).**
  Guiding rule: *start closed, open later* — exporting more later is
  compatible, removing an export breaks users, so anything still an open
  API decision stays internal. Every module has an explicit export list.
  - Public: `Puregrain.Dither` (`ditherImage`, `ditherRows`, and the
    stepper `Dithering`/`initDithering`/`ditherRow`), `.Kernel`, `.Pixel`,
    `.Quantize`, `.Palette`, `.Palette.Presets`, `.Ordered`.
  - `Puregrain` — a facade, re-exports only: what a typical application
    needs plus the types for signatures; building blocks for
    customization (`compilePalette`, `distance2`, `nearestColorFast`,
    `paletteColors`, `compileThresholdMap`, `bayerMatrix`, `thresholdAt`)
    stay in their modules. Docs recommend `import Puregrain as P`. The
    CLI imports only `Puregrain`, so its build checks the facade covers a
    real application.
  - `Puregrain.Internal.*` (`Fifo`, `Kernel` (compiled), `State`, `Step`,
    `Row`, `Image` (`ditherImageWith`, `ditherRowsWith`), `Util`) — exported
    (PureScript has no package-private modules; the tests need them) but
    documented as unstable. `Fifo` and the backend-choosing drivers stay
    internal (decided 2026-10-05).
  - Public doc comments are self-contained (Pursuit shows them): no
    `CLAUDE.md`/test references, absolute GitHub links to `docs/`;
    dev notes go in plain `--` comments. Internal modules may point at
    repo docs.
  - The reshape was verified byte-identical: 17 CLI configurations
    produced the same PNGs before and after.
- `Puregrain.Kernel` — `Kernel` is an opaque, checked `Array Offset`
  (`{dx, dy, weight}`), the same pattern as `ThresholdMap`:
  `fromOffsets :: Array Offset -> Either String Kernel` checks that every
  offset points forward in scan order (`dy > 0`, or `dy == 0 && dx > 0`;
  unchecked, a backward/self offset crashed at the first pixel and
  `dy < 0` was silently dropped), every weight is finite, and no
  neighbour appears twice (rules 2–3 by "start closed": relaxing later
  is compatible). Weight sign and sum aren't checked (Atkinson's 3/4 is
  deliberate). `offsets` reads them back; presets `floydSteinberg`,
  `atkinson`, `jarvisJudiceNinke`, and `noDiffusion` (the empty kernel;
  `[]` is no longer a `Kernel`). The test generator draws distinct
  offsets per row, so its kernels always pass. `Puregrain.Internal.Kernel`:
  `CompiledKernel` (record: `currentOffsets`, `futureLayers`, `maxDepth`)
  is a precomputed cache built once via `compileKernel`, threaded through
  the hot path instead of recomputing `Array.filter`s per pixel
  (PureScript does NOT auto-memoize like GHC sometimes does — this bit us
  once as a real, measured regression).
- `Puregrain.Internal.Fifo` — `class Fifo (f :: Type -> Type)` with 4 methods:
  `replicate`, `enqueue`, `dequeue`, `replace` (shift-left-by-n +
  zero-fill, its own method rather than `drop`+`<>` because that
  composition is O(n) even when n is small — see below). Instances:
  `List.Lazy`, `Data.List` (strict), `Array`, `Data.CatQueue` (registry
  package `catenable-lists`: Okasaki's strict two-list queue).
  **`CatQueue` is the production default** (see Performance below). Its
  O(1) amortized `dequeue` assumes each queue version is used once
  (an old version used again redoes the list reversal) — which is how
  `step`/`stepRow` use them. At the row level, reuse costs nothing
  extra: stepping from an old state redoes that row's work, the
  reversal included, so public `Dithering` states are freely reusable
  (an earlier "use each state once" worry, corrected 2026-10-07).
- `Puregrain.Pixel` — `Gray = Number`; `RGB`/`RGBA` are `newtype`s (not
  `type` aliases — aliases sharing record shape would collide on
  instance resolution) with hand-written `Semiring`/`Ring` (honest
  `mul`/`one`, unused by diffusion but a legitimate algebra) and a
  custom `class Ring a <= Scalable a where scale :: Number -> a -> a`
  (kernel weights are always `Number` regardless of channel count), plus
  `class MapChannels` (+ `Number`/`RGB`/`RGBA` instances).
- `Puregrain.Quantize` — `Quantize a` is opaque: a newtype over
  `Context -> a -> a` whose constructor isn't exported (decided
  2026-10-05, "start closed"), with `type Context = { x :: Int, y :: Int }`
  (the pixel's position). Built by `quantize :: (a -> a) -> Quantize a`
  (position-blind) or `quantizeWith :: (Context -> a -> a) -> Quantize a`
  (uses the position; e.g. `Puregrain.Ordered`), run by `runQuantize`.
  Same power as the constructor, but users can't take one apart, so the
  representation may change (a position-blind flag to skip the
  per-pixel `Context`, a per-row setup) without breaking them. Helpers needing only some
  context fields take `forall r. { x :: Int | r }` (row polymorphism —
  PureScript's answer to Haskell's `HasX` classes), so `Context` can
  grow without breaking them. No Reader monad: a plain function of a
  record, by decision. The scalarED toolkit lives
  here too: `perChannel`, `nearestLevel`, `evenRamp`, `threshold` (see
  scalarED/vectorED below).
- `Puregrain.Palette` — vectorED: `CompiledPalette` (a `NonEmptyArray RGB`
  packed with a swappable distance metric, currently only `distance2`),
  `nearestColorFast`/`nearestColor`. `CompiledPalette` is opaque (read
  the colors with `paletteColors`): the palette search is the next
  performance target and may change its representation. Note `distance2` is plain RGB
  distance, not perceptual: pure green is nearer to black than to white
  (pinned by a test).
- `Puregrain.Palette.Presets` — fixed palettes as plain `NonEmptyArray RGB`
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
- `Puregrain.Ordered` — ordered (Bayer) dithering as an ordinary
  `Quantize Number`, over levels; color via `perChannel`. Pure ordered
  dithering = `noDiffusion`; with any other kernel it's the
  hybrid ("threshold modulation"): the error stays `corrected − q`,
  measured against the value, so diffusion keeps the tones and the map
  only places the dots. `ThresholdMap` is opaque, so every map is
  checked: built by `bayer n` (side, any power
  of 2 incl. 1; `Maybe`, one failure reason, like
  `compilePaletteFromArray`) or `compileThresholdMap` (ranks;
  `Either String`, several failure reasons the caller must tell apart).
  Thresholds `(rank + 0.5) / (maxRank + 1)`; `thresholdAt` takes any
  `{ x, y | r }` (row polymorphism, as planned for `Context` helpers).
  `ordered` sorts the levels once, decides `v − lo > t·(hi − lo)`
  (division-free), is total (clamps; a NaN can't loop), and
  `ordered (bayer 1)` ≡ `nearestLevel` on sorted levels. Against a
  palette (vectorED) it's not supported: TODO.md, and
  docs/ordered-dithering.md "Not supported".
- No JS-facing layer exists right now, by decision: the old
  `Dither.Ffi` (a monomorphic `ditherImageArray` wrapper) was deleted
  once the JS CLI, its only user, was replaced by `puregrain-cli`. The
  npm interface gets designed fresh when the npm package work starts
  — JS can't call typeclass-polymorphic functions (they need instance
  dictionaries), so it will again be a monomorphic layer.
- `Puregrain.Internal.State` / `.Step` / `.Row` / `.Image` — diffusion
  core, polymorphic over `Fifo f` and `Ring a, Scalable a`. Public image
  type (decided 2026-10-06): `Puregrain.Dither.ditherImage` takes and
  returns `Array (Array a)` (in memory, strict) and `ditherRows` a lazy
  `List (Array a)` (streaming): `ditherImageWith`/`ditherRowsWith (Proxy
  CatQueue)`, two thin drivers (a strict `mapAccumL`, a lazy unfold) over
  one `stepRow`, pinned equal by a property in `DitherSpec`. No type
  aliases for rows or images (no safety, hides laziness, `Row` clashes).
  The stepper (decided 2026-10-07): `initDithering kernel quantize`
  builds an opaque `Dithering a` (compiled kernel, quantizer and a
  `DitherState CatQueue a` inside — the old `DitherAlgo` idea, settled
  without a public config record), and `ditherRow :: Dithering a ->
  Array a -> Either String { row, next }` dithers one row. A pure state
  machine: the caller runs the loop, so effectful sources (network
  streams, files) work; it caches nothing; states are reusable (undo).
  The generic `MonadRec` driver stays a TODO.md "future direction".
  `RowLayer f a = Array (f a)`, `DelayLine f a = Array (RowLayer f a)`.
  `current`/`matured`/`building` are row-local (`RowState`); only
  `delayLines`, the row counter `nextRow` and the image `width` (from
  the first row) cross row boundaries (`DitherState`). `stepRow`
  (internal, formerly `ditherRow`) checks each row's length against
  `width` first: a different length is a caller's bug, a `Left` with a
  message naming the row. The public stepper `ditherRow` returns it;
  `ditherImage`/`ditherRows` turn it into a runtime error
  (`unsafeCrashWith`), since their result types have no error channel. `ditherRowsWith`
  does all its work inside `defer`, so each row is read and dithered
  only when its cell is forced (until 2026-10-04 a strict `let` outside
  the `defer` dithered each row one cell early); `DitherSpec` pins it
  (an endless input; an input whose third row crashes when read). Positions: `y` is `DitherState.nextRow` (a caller
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
    `Test.Puregrain.QuantizeSpec`).
  - **vectorED** — the quantizer sees the whole pixel at once, e.g.
    `Puregrain.Palette.nearestColor` (nearest palette color by a distance
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
  count is (the `<>` walks the whole kept prefix). `CatQueue` does it
  as `skip` dequeues + `skip` enqueues: O(skip), and `skip` is at most
  the kernel's reach. (The former default, the finger tree `Seq`, used
  its O(log n) concatenation.)
- **`ST` doesn't fit the `Fifo` abstraction**: `enqueue`/`dequeue` are
  called from separate call sites across a value's lifetime (not one
  `runST` block), so real `O(1)` mutation there would require either
  unsafe linear-use assumptions or a hand-rolled consumed-flag +
  defensive-copy scheme — both rejected as not worth it given
  `CatQueue` already achieves the target asymptotic complexity. A genuinely
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

2026-10-03: `Seq` (from a git fork of `sequences`, which blocked
publishing) was replaced by `Data.CatQueue`: ~3.6× faster again
(median over configurations; JJN ~6×), and the library now depends
only on registry packages. With the queue no longer dominant, the RGB
arithmetic and the palette search are the next costs
(`docs/benchmarks-dithering.md`).

## Testing

`Test.Puregrain.Reference` — an independent, deliberately naive
`ST`-based two-loop reference implementation (no `Fifo`/padding
machinery), used as a QuickCheck oracle. `Test.Puregrain.Arbitrary`
generates random `Kernel`s and images. `Test.Puregrain.DiffusionMechanicsSpec`
checks every `Fifo` backend against the reference on random inputs —
this is what actually caught real bugs (see Gotchas below), where
hand-picked example kernels (Floyd–Steinberg, Atkinson, JJN — all
`maxDepth ≥ 1`) did not.

Library specs are flat `Test.Puregrain.<Name>Spec` modules, one per
module tested (e.g. `PixelSpec`, `QuantizeSpec`, `RowSpec`). `Test.Main`
discovers them with `^Test\.Puregrain\.[A-Za-z]+Spec$`: spec-discovery
runs an unanchored `RegExp.test` over the shared `output/`, and the
anchors plus the single name segment keep out the CLI's
`Test.Puregrain.Cli.*` specs, which the CLI lists explicitly.

The documented exact checks (docs/test-images.md → "Exact checks") are
deliberately tested twice, at two levels: as Spec properties over
arbitrary kernels/palettes/images ("whole images" blocks in
`PaletteSpec`/`PixelSpec`/`OrderedSpec`), and end to end through the real CLI on the
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

- **`where`/`let` bindings are strict**, evaluated before the body: a
  check in the body runs after them (`stepRow`'s row-length check
  first ran after the row had already crashed), and a lazy-list cell
  built after a `let` doesn't delay that `let`. Put the work in the
  branch or the `defer` that should guard it.
- **In an `Effect` do-block, a leading `let` is evaluated when the
  effect is built, not when it runs** (`do let x = e; …` is just
  `let x = e in …`), so `try` can't catch an error it throws. Delay it
  behind a bind: `pure unit >>= \_ -> pure (f unit)` (`whenRun` in
  `Test.Puregrain.DitherSpec`).

- **A `where` after guards belongs to the last guard only** — unlike
  Haskell, where it scopes over all of them. `f n | c = g n | otherwise
  = h where g = …` fails with "Unknown value g" in the first guard.
  Use `if`/`case` instead, or put the shared bindings in a `where` of an
  unguarded equation (as in `Puregrain.Ordered.bayerMatrix`).

- **`(..)` is NOT empty when reversed**: `1 .. 0` evaluates to `[1, 0]`
  (descending), NOT `[]` like Haskell's `[1..0]`. This caused a real,
  QuickCheck-caught bug whenever `maxDepth == 0` (a legitimately valid
  kernel with no cross-row diffusion). Fixed via `Puregrain.Internal.Util.safeRange`
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

- The workflow rules — branches (`master`, short-lived branches only for
  risky work), CI, versions, releases — are in `CONTRIBUTING.md`; follow
  them. `npm run check` runs what CI (`.github/workflows/ci.yml`) runs:
  build with `--pedantic-packages --strict`, both test suites,
  `check:cli`. Keep the two in step.
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
