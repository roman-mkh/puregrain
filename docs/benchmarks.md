# PureGrain — Benchmarks

This document tracks performance measurements of the dithering pipeline
over time, as different backends and optimizations are introduced.
Each dated section is a self-contained benchmark run — new sections are
appended below rather than overwriting previous ones, so regressions
and improvements stay visible.

---

## 2026-09-09 — Floyd–Steinberg scaling (classic FIFO backend, pre-optimization)

**Backend:** classic (`Data.List.Lazy`-based FIFO, `mapAccumL`-driven
`step`/`ditherRow`/`ditherImage`, as of the `RowState { current, matured,
building }` architecture).

**Kernel:** Floyd–Steinberg. **Quantizer:** binary threshold (128).

### Method

Five square (`N×N`) grayscale PNGs were generated with proportionally
identical content (horizontal gradient + shaded circle), for
`N ∈ {64, 128, 256, 512, 1024}`. Each was dithered via
`scripts/dither-cli.mjs`, wall-clock timed end-to-end (process start to
exit, including PNG decode/encode) with the Unix `time` builtin:

```bash
for s in 64 128 256 512 1024; do
  time node scripts/dither-cli.mjs samples/bench/bench-$s.png /tmp/out-$s.png floyd-steinberg
done
```

**Environment:** user's local machine — *(fill in: `node --version`, OS/CPU,
`spago`/`purs` versions, for reproducibility)*.

### Results

| Side N | Pixels (N²) | Time (real) | Ratio vs. previous N |
|-------:|------------:|------------:|----------------------:|
|     64 |       4,096 |      0.213s |                      — |
|    128 |      16,384 |      0.633s |                  ×2.97 |
|    256 |      65,536 |      3.807s |                  ×6.02 |
|    512 |     262,144 |     32.388s |                  ×8.51 |
|   1024 |   1,048,576 |    289.295s |                  ×8.93 |

![Time vs. image side, log-log scale, with an O(N³) reference line](images/scaling-floyd-steinberg.png)

### Analysis

The per-doubling ratio climbs toward **×8**, which is the signature of
**cubic** growth (`2³ = 8`) in the side length `N` — visible on the
log-log plot as convergence onto the dashed `O(N³)` reference line. The
lower ratios at small `N` (×2.97, ×6.02) are consistent with fixed
per-process overhead (Node startup, V8 warmup, PNG codec) diluting as
`N` grows, rather than contradicting the cubic hypothesis.

For a square image, `O(N³) = O(width² × height)` — i.e. **quadratic in
row width, linear in height**. This points at per-row cost, not
per-image cost, as the quadratic culprit.

**Leading suspect:** `Dither.Row.commitBuilding` accumulates each
`building` `RowLayer` via repeated `enqueueWeighted` (`Data.List.Lazy`
`snoc`) — one call per pixel in the row. `snoc` on a singly-linked list
is `O(n)` in the current length, so accumulating a layer across a row of
width `w` costs `1 + 2 + ... + w = O(w²)`, not `O(w)`. Across `h` rows,
total cost is `O(w² · h)` — matching the observed `O(N³)` on square
(`w = h = N`) inputs exactly.

Secondary, non-asymptotic overheads noted separately (see `TODO.md`):
`K.currentOffsets`/`K.offsetsForDy` are re-filtered from `Kernel` on
every pixel inside `step` rather than precomputed once; a few pixels'
worth of wasted work at row/image edges from padding/skip.

### Next steps

- Fix the suspected `O(n)` `snoc` cost in `building` accumulation
  (candidates: `Data.Sequence`, `cons` + single `reverse` per row, or an
  `ST`-based strict array for this hot path — see `TODO.md`).
- Precompute `Kernel`-derived offset arrays once per image/row instead
  of inside `step`.
- Re-run this exact scaling test after the fix and append results below
  for direct before/after comparison.

---

## 2026-09-13 — SeededFifo regression, then CompiledKernel fix

**Context:** two architectural changes were made since the previous
entry, both measured with the same method/images as above (Floyd–
Steinberg, binary threshold 128).

1. **`SeededFifo`** was introduced to remove the last infinite lazy
   structure (`LL.repeat 0.0`) from `DelayLine`/`matured`, as a
   prerequisite for pluggable strict backends (a `Constant Number | Real
   Fifo` wrapper can't be represented by, e.g., a plain strict `Array`).
   This alone was a **regression**: wrapping/unwrapping `SeededFifo` on
   every pixel × offset added a real (compiled-JS-confirmed) extra
   allocation to the hot loop.
2. **`CompiledKernel`** was introduced as a separate fix: a precomputed
   record (`currentOffsets`, `futureLayers`, `maxDepth`) built once via
   `compileKernel` at the top of `ditherImage`, replacing repeated
   `Array.filter`-based lookups (`K.currentOffsets kernel`,
   `K.offsetsForDy kernel dy`) that were happening on *every pixel*
   inside `step` — a separate, always-present inefficiency identified
   during the original profiling discussion, predating `SeededFifo`.
   The `SeededFifo` unwrap was also moved from per-pixel to per-row
   (`resolveSeededLayer`, called once per row using the now-known row
   width), eliminating the regression from (1) at the same time.

### Results

| Side N | Baseline (prev. entry) | SeededFifo (regression) | + CompiledKernel |
|-------:|------------------------:|--------------------------:|-------------------:|
|     64 |                  0.213s |                    0.335s |             0.200s |
|    128 |                  0.633s |                    1.027s |             0.628s |
|    256 |                  3.807s |                    5.917s |             3.490s |
|    512 |                 32.388s |                   47.335s |            30.488s |
|   1024 |                289.295s |                  447.050s |           284.585s |

![Three rounds compared, log-log, with an O(N³) reference line](images/scaling-compiled-kernel.png)

### Analysis

`+ CompiledKernel` is not just "back to baseline" — it's **slightly
faster** across the board (1-8%), because it fixed two overlapping
issues at once: the `SeededFifo` regression *and* the pre-existing
per-pixel `Array.filter` cost that was already present in the original
baseline entry but hadn't been addressed yet.

Growth ratios per doubling (`+ CompiledKernel`): ×3.14, ×5.56, ×8.74,
×9.33 — statistically indistinguishable from the original entry's
×2.97, ×6.02, ×8.51, ×8.93. **The `O(N³)` asymptotic behavior is fully
intact.** This refactor improved the constant factor only, exactly as
predicted going in — the dominant cost (suspected `O(n)` `snoc` in
`building` accumulation) is untouched.

### Next steps

Unchanged from the previous entry: the real fix is a pluggable `class
Fifo` abstraction with an `O(1)`-amortized backend (`Data.Sequence` /
`purescript-queue`) replacing `Data.List.Lazy`'s `O(n)` `snoc` in the
hot path. That work is in progress; this entry exists to keep the
historical record honest about what has and hasn't been fixed so far.
