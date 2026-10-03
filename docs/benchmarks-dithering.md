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
npm run bench -- --json samples/bench/results.json > samples/bench/results.md   # ~11 min on mains
node scripts/plot-benchmarks.mjs samples/bench/results.json docs/images/benchmarks-dithering-<date>.svg
node scripts/benchmark.mjs --report samples/bench/results.json   # the tables again, without measuring
npm run clean:bench   # delete the generated images in samples/bench/ (keeps the results)
```

Options: `--runs` (default 5), `--sizes` (default `64,128,256,512,1024`),
`--suite modes|kernels|all` (default `all`). Plug the laptop in, close
other programs, and leave the machine alone until the run ends; see
[Noise](#noise-1) for why.

To measure an older commit, for example as the baseline for a change,
check it out in a separate git worktree, link `node_modules` from the
main checkout, build it there and run that worktree's
`scripts/benchmark.mjs`: each checkout benchmarks its own build.

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
  over all configurations instead of landing on the last ones. A burst
  of load lands on one round instead, so the report also counts, per
  round, how many configurations had their slowest run in it ("Slowest
  run by round"). One round holding most of them points to an outside
  disturbance during that round.
- **Growth per doubling** of the image side is reported over the three
  largest sizes, as a geometric mean of two steps. A single step can be
  thrown off by one noisy median. ×4 per doubling means time proportional
  to the pixel count.
- **Power source:** on a laptop, battery power management changes the
  CPU's clock speed, so compare only runs made on the same power source.
  The script records it (mains or battery) in the Environment block.
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
- Power: **battery** (the laptop was unplugged; noted afterwards, since
  the script didn't record the power source yet). Compare later runs
  with this one only if they also ran on battery.
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

Two possible explanations, neither verified. The run was on **battery**,
where the laptop's power management changes clock speeds from moment to
moment. And the machine is a Hyper-V virtual machine on a hybrid CPU with
both performance and efficiency cores, so a virtual core may sometimes run
on a faster physical core than usual. A rerun on mains power would show
how much of the spread the battery accounts for.
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
- **Reduce the noise** before relying on differences under 20%: first a
  rerun on mains power, then if needed bare metal or a core reserved for
  the benchmark.
- **The `nearestLevel` binary search** (`TODO(benchmark)` in
  `Dither.Pixel`) looks low priority now: `--levels 4` costs only ×1.06 of
  a threshold. It could still matter at level counts far above 4.


---

## 2026-10-03 — Baseline on mains power

The 2026-09-25 baseline ran on battery, so this is the same measurement
again on mains power. It's the baseline for later runs, which should run
on mains too.

A first attempt earlier the same day was disturbed: the machine was in
use during part of the run. 19 of its 21 configurations from 256² up had
their slowest run in the same round (round 4), and its spread was a
median of 34%. That pattern is what the report's "Slowest run by round"
line now flags. Its medians differed from this run's by ×0.86 to ×1.12,
so it was discarded and the run repeated with the machine left alone.

**Environment:**

- Commit `dbb3416`, built in a separate git worktree. The script reports
  it as having uncommitted changes; the only one is that worktree's link
  to the main checkout's `node_modules`. The dithering code is the same as
  in `f603796`, the commit of the 2026-09-25 run: in between, only the
  palettes moved to `Dither.Palette.Presets`, and the CLI gained the new
  palettes.
- CPU: Intel Core Ultra 9 185H (11 logical cores), inside a Hyper-V
  virtual machine; memory: 31 GiB
- Power: mains (AC)
- OS: Linux 6.8.0-1065-azure (x64)
- Node v22.14.0; purs 0.15.16; spago 1.0.4
- 5 runs per configuration, interleaved; median reported

### Results

**Quantizer modes** (Floyd–Steinberg; median ms, with growth over the
previous size):

| Side N | Pixels | threshold 128 | levels 4 (gray) | levels 6 (RGB) | websafe216 | bw |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 4,096 | 86.0 | 88.1 | 86.0 | 103 | 89.4 |
| 128 | 16,384 | 136 (×1.58) | 148 (×1.68) | 191 (×2.22) | 243 (×2.37) | 182 (×2.04) |
| 256 | 65,536 | 491 (×3.62) | 527 (×3.57) | 647 (×3.39) | 806 (×3.31) | 643 (×3.53) |
| 512 | 262,144 | 1,955 (×3.98) | 1,825 (×3.46) | 2,836 (×4.38) | 3,586 (×4.45) | 2,284 (×3.55) |
| 1024 | 1,048,576 | 7,893 (×4.04) | 8,329 (×4.56) | 12,047 (×4.25) | 15,529 (×4.33) | 10,194 (×4.46) |
| per doubling, 256²→1024² | | ×4.01 | ×3.97 | ×4.32 | ×4.39 | ×3.98 |

**Cost relative to threshold 128, at 1024²:** levels 4 (gray) ×1.06;
levels 6 (RGB) ×1.53; websafe216 ×1.97; bw ×1.29. websafe216 ÷ levels 6
(RGB), which give identical output: ×1.29.

**Kernels** (threshold 128, gray; median ms):

| Side N | floyd-steinberg | atkinson | jjn | atkinson ÷ FS | jjn ÷ FS |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 86.0 | 88.2 | 127 | ×1.03 | ×1.47 |
| 128 | 136 | 191 | 385 | ×1.41 | ×2.84 |
| 256 | 491 | 653 | 1,526 | ×1.33 | ×3.11 |
| 512 | 1,955 | 2,771 | 6,259 | ×1.42 | ×3.20 |
| 1024 | 7,893 | 11,102 | 26,106 | ×1.41 | ×3.31 |
| per doubling, 256²→1024² | ×4.01 | ×4.12 | ×4.14 | | |

**Run-to-run spread** ((max − min) ÷ median): median 12% for sizes 256²
to 1024² (largest 37%, websafe216 at 256²); median 15% over all sizes.
**Slowest run by round** (256² to 1024², rounds 1–5): 5 / 1 / 5 / 4 / 6:
no round stands out.

![Median dithering time on mains power against image side for five quantizer modes, log-log: all five rise roughly in parallel with the dashed O(N²) reference from 256² up, and bend above it at the smallest sizes](images/benchmarks-dithering-2026-10-03-mains.svg)

### Analysis

**On mains, dithering takes about a quarter less time than on battery.**
From 256² up, the medians are ×0.65 to ×0.83 of the battery baseline's,
×0.73 in the median, in all 21 configurations. Floyd–Steinberg with a
threshold now takes 7.9 s at 1024²: about 7.5 µs per pixel, or 133,000
pixels per second. That's the number future optimizations should beat.

**The other conclusions of the battery baseline still hold.**

- Each doubling of the side multiplies the time by ×3.97 to ×4.39
  between 256² and 1024²: proportional to the pixel count. Floyd–Steinberg
  with a threshold takes 7.5 µs per pixel at 256², 512² and 1024² alike.
- Time per kernel still tracks the number of neighbours: Atkinson takes
  ×1.33 to ×1.42 of Floyd–Steinberg (×1.5 predicted), JJN ×3.11 to ×3.31
  (×3 predicted).
- The quantizers are still cheap next to the diffusion: `--levels 4`
  costs ×1.06 of a threshold, and RGB `--levels 6` ×1.53, not ×3.
- Searching the 216 web-safe colors costs ×1.25 to ×1.29 of `--levels 6`,
  which gives identical output (256² to 1024²).

**websafe216's runs vary the most,** for example 791 to 1,085 ms at 256².
Its numbers at a single size are the least reliable here.

### Noise

**The battery accounts for most of the 2026-09-25 spread.** That run's
outliers were fast runs: from 256² up, 10 of the 21 configurations had a
run more than 15% faster than their median, and only 1 had a run more
than 15% slower. Those fast runs were about as fast as a typical run on
mains (×0.79 to ×1.13 of this run's medians). Here, only 1 configuration
has such a fast run and 2 have such a slow one, and the spread drops from
a median of 21% to 12%. So on battery the CPU mostly ran slower, with an
occasional run at full speed. That was the first of the two explanations
offered there.

**Within one run, the middle three of each configuration's five runs lie
within about 4% of each other** (median over the configurations; the same
on battery). So differences of about 10% or more between configurations
in one run are real, except for websafe216's. How much two separate runs
differ is measured in the next section.

### Next steps

- **Try `Data.CatQueue` as the `Fifo`:** a ready-made two-list queue
  (Okasaki's design) from the registry package `catenable-lists`
  ([TODO.md](../TODO.md)). The queue work still looks like the main
  cost, and the change would also remove the git-only `sequences`
  dependency.
- **Confirm linear scaling at 2048² and 4096²,** still open from
  benchmarks-fifo.md. One mode is enough.
- **The `nearestLevel` binary search** (`TODO(benchmark)` in
  `Dither.Pixel`) stays low priority: `--levels 4` costs ×1.06 of a
  threshold.

---

## 2026-10-03 — Quantizer with the pixel's position (`Context`)

`Quantize a` changed from `Quantize (a -> a)` to
`Quantize (Context -> a -> a)`, with `type Context = { x :: Int, y :: Int }`:
every call now gets the position of the pixel it quantizes, which Bayer
and noise dithering will need. No quantizer uses the position yet, so
this run measures what passing it costs: one small record per pixel, and
two more fields in the row state that `step` already rebuilds for every
pixel. The run is also the reference for the next change, the `Fifo`
backend. It ran right after the baseline above, with the machine left
alone; a first attempt was discarded along with the baseline's.

**Environment:**

- Commit `5242b7c` (the `Context` change), plus uncommitted changes to
  docs only
- CPU: Intel Core Ultra 9 185H (11 logical cores), inside a Hyper-V
  virtual machine; memory: 31 GiB
- Power: mains (AC)
- OS: Linux 6.8.0-1065-azure (x64)
- Node v22.14.0; purs 0.15.16; spago 1.0.4
- 5 runs per configuration, interleaved; median reported

### Results

**Quantizer modes** (Floyd–Steinberg; median ms, with growth over the
previous size):

| Side N | Pixels | threshold 128 | levels 4 (gray) | levels 6 (RGB) | websafe216 | bw |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 4,096 | 87.6 | 81.6 | 88.3 | 93.0 | 79.9 |
| 128 | 16,384 | 144 (×1.64) | 147 (×1.81) | 195 (×2.21) | 267 (×2.87) | 183 (×2.29) |
| 256 | 65,536 | 463 (×3.23) | 499 (×3.39) | 632 (×3.24) | 961 (×3.60) | 582 (×3.18) |
| 512 | 262,144 | 1,901 (×4.10) | 1,818 (×3.64) | 2,764 (×4.37) | 3,722 (×3.87) | 2,392 (×4.11) |
| 1024 | 1,048,576 | 7,797 (×4.10) | 7,830 (×4.31) | 12,171 (×4.40) | 15,497 (×4.16) | 10,338 (×4.32) |
| per doubling, 256²→1024² | | ×4.10 | ×3.96 | ×4.39 | ×4.02 | ×4.22 |

**Cost relative to threshold 128, at 1024²:** levels 4 (gray) ×1.00;
levels 6 (RGB) ×1.56; websafe216 ×1.99; bw ×1.33. websafe216 ÷ levels 6
(RGB), which give identical output: ×1.27.

**Kernels** (threshold 128, gray; median ms):

| Side N | floyd-steinberg | atkinson | jjn | atkinson ÷ FS | jjn ÷ FS |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 64 | 87.6 | 85.3 | 130 | ×0.97 | ×1.48 |
| 128 | 144 | 205 | 400 | ×1.42 | ×2.79 |
| 256 | 463 | 672 | 1,496 | ×1.45 | ×3.23 |
| 512 | 1,901 | 2,710 | 5,997 | ×1.43 | ×3.16 |
| 1024 | 7,797 | 11,192 | 26,030 | ×1.44 | ×3.34 |
| per doubling, 256²→1024² | ×4.10 | ×4.08 | ×4.17 | | |

**Run-to-run spread** ((max − min) ÷ median): median 9% for sizes 256² to
1024² (largest 21%, websafe216 at 256²); median 11% over all sizes.
**Slowest run by round** (256² to 1024², rounds 1–5): 2 / 7 / 3 / 3 / 6:
no round stands out.

![Median dithering time with the Context change against image side for five quantizer modes, log-log: all five rise roughly in parallel with the dashed O(N²) reference from 256² up, and bend above it at the smallest sizes](images/benchmarks-dithering-2026-10-03-context.svg)

**Against the mains baseline** (this run's median ÷ the baseline's):

| Configuration | 256² | 512² | 1024² |
| --- | ---: | ---: | ---: |
| Floyd–Steinberg, threshold 128 | ×0.94 | ×0.97 | ×0.99 |
| Floyd–Steinberg, levels 4 (gray) | ×0.95 | ×1.00 | ×0.94 |
| Floyd–Steinberg, levels 6 (RGB) | ×0.98 | ×0.97 | ×1.01 |
| Floyd–Steinberg, websafe216 | ×1.19 | ×1.04 | ×1.00 |
| Floyd–Steinberg, bw | ×0.90 | ×1.05 | ×1.01 |
| Atkinson, threshold 128 | ×1.03 | ×0.98 | ×1.01 |
| JJN, threshold 128 | ×0.98 | ×0.96 | ×1.00 |

### Analysis

**Passing the position costs nothing measurable.** From 256² up, the
medians are ×0.99 of the baseline's in the median (×0.90 to ×1.19), and
×1.00 at 1024², where the cold start matters least (×0.94 to ×1.01).
14 configurations got faster and 7 slower. Comparing each configuration's
fastest run instead of its median also gives ×1.00 in the median (×0.97
to ×1.09). Whatever the record costs is lost in the noise.

**Two quiet runs of nearly the same code differ by about 2.5% per
configuration.** That's the difference between runs that the baseline's
Noise section left open. 16 of the 21 configurations are within 5% of
each other, and 20 within 10%; the exception is websafe216 at 256²
(×1.19), whose runs vary the most anyway. The discarded first attempts
differed from each other by up to 17%. So with the machine left alone, a
change compared across two runs shows when it beats about 5% consistently
over the configurations, and clearly when it beats 10%. Anything smaller
needs both versions measured in the same run.

**websafe216 again varies the most,** for example 13.6 to 15.9 s at
1024². Its cost over `--levels 6` is ×1.27 at 1024², matching the
baseline's ×1.29; at the smaller sizes it scatters (×1.52 and ×1.35).

### Next steps

- **`Data.CatQueue` as the `Fifo`** is next, compared against this run.
  If its gain is under about 5%, it would only show with both backends
  measured in the same run, interleaved: for example by letting one build
  run either backend. To be decided with that step.
- The other next steps of the mains baseline still apply.
