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
scriptDir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
for s in 64 128 256 512 1024; do
  echo "=== size $s ==="
  time node ${scriptDir}/../../scripts/dither-cli.mjs ${scriptDir}/bench-$s.png /tmp/out-$s.png floyd-steinberg
done
```

**Environment:** user's local machine — *(fill in: `node --version`, OS/CPU,
`spago`/`purs` versions, for reproducibility)*.
* `node --version`: v22.14.0
* `spago --version` v1.0.4
* `purs --version`: v0.15.16

```
uname -a
lscpu | grep -E 'Model name|CPU\(s\):|Thread|Core'
nproc
Linux thalia 6.8.0-1065-azure #73~22.04.1-Ubuntu SMP Wed Aug 12 23:21:42 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
CPU(s):                                  11
Model name:                              Intel(R) Core(TM) Ultra 9 185H
Thread(s) per core:                      2
Core(s) per socket:                      6
NUMA node0 CPU(s):                       0-10
```

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
