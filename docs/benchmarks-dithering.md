# PureGrain — Benchmarks: dithering

The current performance of the dithering pipeline, measured through the
real CLI, for each quantizer mode and kernel. Each dated section is one
self-contained run. New runs are appended as new sections rather than
overwriting old ones, so improvements and regressions stay visible.

The investigation that found and fixed the O(N³) scaling bug by choosing
the `Seq` `Fifo` backend is a finished record in
[benchmarks-fifo.md](benchmarks-fifo.md). Its numbers aren't comparable
with these: they were measured with a different CLI, on different images,
and as whole-process time.

## How to reproduce

```bash
npm run build
npm run bench -- --json samples/bench/results.json > samples/bench/results.md   # ~15 min
node scripts/plot-benchmarks.mjs samples/bench/results.json docs/images/benchmarks-dithering-<date>.svg
node scripts/benchmark.mjs --report samples/bench/results.json   # the tables again, without measuring
```

Options: `--runs` (default 5), `--sizes` (default `64,128,256,512,1024`),
`--suite modes|kernels|all` (default `all`). Close other programs first;
see [Noise](#noise) for why.

## Method

- **What's timed:** the CLI's `Dithered in … ms` line. That covers the
  library's `ditherImage` only: not PNG decoding or encoding, not gray
  conversion, not Node startup (see [cli/README.md](../cli/README.md#output-and-timing)).
- **A fresh process for every run,** because that's how the CLI is used.
  V8 compiles the dithering code during the timed part, which adds a
  fixed cold-start cost of roughly 0.05–0.1 s. It dominates the time at
  64² and 128² and is negligible from 256² up.
- **5 runs per configuration; the median is reported.** Runs are
  interleaved: round 1 of every configuration, then round 2, and so on.
  Slow drift during the run (heat, background load) therefore spreads
  over all configurations instead of landing on the last ones.
- **Growth per doubling** of the image side is reported over the three
  largest sizes, as a geometric mean of two steps. A single step can be
  thrown off by one noisy median. ×4 per doubling means time proportional
  to the pixel count.
- **Inputs:** the generated composites from
  [test-images.md](test-images.md), the gray composite for the gray modes
  and the color composite for the RGB modes. The content doesn't affect
  timing: every quantizer does the same work per pixel whatever the pixel's
  value.
- **Two suites:**
  - **Modes:** five quantizer modes, all with Floyd–Steinberg. RGB uses
    `--levels 6` so it compares directly with `--palette websafe216`: the
    two produce byte-identical output.
  - **Kernels:** the three kernels, all on the default `--threshold 128`
    with the gray composite.

---

## 2026-09-25 — Baseline: quantizer modes and kernels

The first measurement with the PureScript CLI and the generated test
images.

**Environment:**

- Commit `f603796`, plus uncommitted changes to docs and scripts only (no
  change to the library or CLI code)
- CPU: Intel Core Ultra 9 185H (11 logical cores), inside a Hyper-V
  virtual machine; memory: 34 GiB
- OS: Linux 6.8.0-1065-azure (x64)
- Node v22.14.0; purs 0.15.16; spago 1.0.4
- 5 runs per configuration, interleaved; median reported

### Results

**Quantizer modes** (Floyd–Steinberg; median ms, with growth over the
previous size):

| Side N | Pixels | threshold 128 | levels 4 (gray) | levels 6 (RGB) | websafe216 | bw |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 4,096 | 104 | 116 | 125 | 158 | 132 |
| 128 | 16,384 | 227 (×2.19) | 238 (×2.05) | 297 (×2.37) | 365 (×2.32) | 270 (×2.04) |
| 256 | 65,536 | 679 (×3.00) | 697 (×2.93) | 941 (×3.16) | 1,188 (×3.25) | 845 (×3.13) |
| 512 | 262,144 | 2,580 (×3.80) | 2,715 (×3.89) | 3,851 (×4.09) | 5,510 (×4.64) | 3,454 (×4.09) |
| 1024 | 1,048,576 | 10,780 (×4.18) | 11,379 (×4.19) | 16,569 (×4.30) | 18,640 (×3.38) | 14,794 (×4.28) |
| per doubling, 256²→1024² | | ×3.98 | ×4.04 | ×4.20 | ×3.96 | ×4.18 |

**Cost relative to threshold 128, at 1024²:** levels 4 (gray) ×1.06;
levels 6 (RGB) ×1.54; websafe216 ×1.73; bw ×1.37. websafe216 ÷ levels 6
(RGB), which give identical output: ×1.13.

**Kernels** (threshold 128, gray; median ms):

| Side N | floyd-steinberg | atkinson | jjn | atkinson ÷ FS | jjn ÷ FS |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 104 | 132 | 213 | ×1.28 | ×2.05 |
| 128 | 227 | 309 | 583 | ×1.36 | ×2.57 |
| 256 | 679 | 934 | 2,059 | ×1.37 | ×3.03 |
| 512 | 2,580 | 4,163 | 8,349 | ×1.61 | ×3.24 |
| 1024 | 10,780 | 15,859 | 35,440 | ×1.47 | ×3.29 |
| per doubling, 256²→1024² | ×3.98 | ×4.12 | ×4.15 | | |

**Run-to-run spread** ((max − min) ÷ median): median 21% for sizes 256²
to 1024² (largest 53%); median 42% over all sizes, where the smallest are
mostly cold start.

![Median dithering time against image side for five quantizer modes, log-log: all five rise in parallel with the dashed O(N²) reference from 256² up, and bend above it at the smallest sizes](images/benchmarks-dithering-2026-09-25.svg)

### Analysis

**Every mode and every kernel scales linearly with the pixel count.**
Between 256² and 1024², each doubling of the side multiplies the time by
×3.96 to ×4.20, against ×4 for time proportional to pixels. So the `Seq`
fix recorded in benchmarks-fifo.md holds for all quantizer modes and for
the kernels with two rows of look-ahead (Atkinson, JJN). That answers an
open "next step" from that doc, which asked whether the fix generalizes
beyond Floyd–Steinberg.

**The absolute rate is about 10 µs per pixel:** 10.8 s for 1.05 million
pixels with Floyd–Steinberg and a threshold, roughly 100,000 pixels per
second. That's the number future optimizations should beat.

**The diffusion machinery costs more than the quantizers.** Several
results point the same way:

- `--levels 4` on gray costs only ×1.06 of a plain threshold. A 4-level
  nearest search per pixel is nearly free next to the rest.
- RGB with `--levels 6` costs ×1.54 of gray, not ×3, even though it
  handles three channels.
- Per kernel, time tracks the number of neighbours each pixel's error is
  sent to. Each of those neighbours means one queue insertion and one
  removal per pixel. Atkinson has 6 against Floyd–Steinberg's 4, predicting
  ×1.5; measured ×1.37–1.61. JJN has 12, predicting ×3; measured ×3.03–3.29.

So the cheapest way to speed up every mode at once is probably the queue
itself: see the banker's-queue idea in [TODO.md](../TODO.md).

**Searching all 216 web-safe colors costs little more than looking up 6
levels per channel.** The two give identical output. The palette search
took ×1.13 as long at 1024², and ×1.26 and ×1.43 at 256² and 512². So it
adds roughly 10–40%, not the multiples that 216 distance computations
against 18 level comparisons might suggest, again because the diffusion
around it dominates. `--palette bw` (×1.37) is cheaper than RGB `--levels
6` (×1.54): it compares only 2 colors.

**Cold start.** The dashed O(N²) line through the 1024² threshold point
predicts 42 ms at 64²; the measured time is 104 ms. The difference, about
0.06 s, is paid once per process. That's why every curve bends above the
line on the left of the chart, and why the growth from 64² to 128² is
only about ×2.

### Noise

The spread between runs is large for a benchmark: a median of 21% from
256² up. It isn't random scatter. Most configurations form a tight cluster:
Floyd–Steinberg at 512² ran 2,546–2,706 ms, and JJN at 1024²
35,059–36,330 ms. The spread comes from occasional runs 20–40% **faster**
than the rest, never slower, such as 404 ms among runs of 665–755 ms.

A possible explanation, not verified: the machine is a Hyper-V virtual
machine on a hybrid CPU with both performance and efficiency cores, so a
virtual core may sometimes run on a faster physical core than usual.
Medians of 5 absorb a single outlier, but a single size step can still be
off. websafe216's ×4.64 and then ×3.38 average to ×3.96 per doubling.
Differences under about 20% between two configurations need more runs, or
a quieter machine, before they mean anything.

### Next steps

- **Try the banker's-queue `Fifo`** ([TODO.md](../TODO.md)). The results
  above suggest the queue work dominates every mode, and the change would
  also remove the git-only `sequences` dependency. Benchmark it as a new
  section here.
- **Confirm linear scaling at 2048² and 4096²,** still open from
  benchmarks-fifo.md. One mode is enough.
- **Reduce the noise** (bare metal, or a core reserved for the benchmark)
  before relying on differences under 20%.
- **The `nearestLevel` binary search** (`TODO(benchmark)` in
  `Dither.Pixel`) looks low priority now: `--levels 4` costs only ×1.06 of
  a threshold. It could still matter at level counts far above 4.
