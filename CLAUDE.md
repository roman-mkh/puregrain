# puregrain — project memory

A PureScript library for dithering (Floyd–Steinberg, Atkinson, JJN, ...),
targeting eventual publication on Pursuit + an npm wrapper. This file
captures architectural decisions and rationale from the design
conversation that built this codebase, since a lot of it isn't visible
from the code alone.

@docs/benchmarks.md
@TODO.md

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
  `newtype Quantize a = Quantize (a -> a)`.
- `Dither.State` / `Dither.Step` / `Dither.Row` / `Dither.Image` —
  diffusion core, polymorphic over `Fifo f` and `Ring a, Scalable a`.
  `RowLayer f a = Array (f a)`, `DelayLine f a = Array (RowLayer f a)`.
  `current`/`matured`/`building` are row-local (`RowState`); only
  `delayLines` crosses row boundaries (`DitherState`).

## Key design decisions (with rationale)

- **Multi-channel model**: N channels are always independent parallel
  copies of the same scalar algorithm *unless* the quantizer looks at
  the whole vector at once (palette/"vector ED", needed for
  image-dependent-palette output). Channel *count* never changes mid-
  pipeline — RGBA→grayscale, palette generation, etc. all happen
  *outside* this library (FFI/caller side), not inside `quantize`.
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

## Performance (see `docs/benchmarks.md` for full history + charts)

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
  reproducible method + chart in `docs/benchmarks.md`, including
  negative/regression results, not just wins.
