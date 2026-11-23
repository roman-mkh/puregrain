# Error diffusion

Error diffusion rounds each pixel to the nearest value it may take, and
passes the rounding error on to pixels not yet processed, which then start
from a corrected value. Each pixel takes only allowed values, yet the
average tone stays right. Where the error goes, and in what shares, is
the *kernel*.

puregrain has 11 ready-made kernels, in the library (`Puregrain.Kernel`,
also in the facade `Puregrain`) and in the CLI (`--kernel NAME`, see
[cli/README.md](../cli/README.md#kernels)), and takes your own as a list
of offsets.

## How it works

The image is processed row by row, top to bottom, each row left to right
(or, with [serpentine scanning](#serpentine-scanning), every other row
right to left). For each pixel:

```
corrected = input(x, y) + error arriving from earlier pixels
q         = quantize(corrected)          (the nearest allowed value)
err       = corrected − q                (sent on: each neighbour gets weight × err)
```

A kernel can only send error forward, to pixels not yet processed: further
right in the same row, or to rows below. Most kernels' weights add up to
1, so all the error is passed on and the tones stay true; Atkinson's add
up to 3/4.

The kernels differ in how far the error spreads, and in its shares. Each
neighbour costs the same time per pixel, so time grows with their number:
at 1024 × 1024, Atkinson's 6 neighbours take about 1.5 times as long as
Floyd–Steinberg's 4, and Jarvis–Judice–Ninke's 12 take 2.3 to 2.5 times as
long ([benchmarks](benchmarks-dithering.md)). The other kernels haven't
been measured yet.

The quantizer decides which values a pixel may take: a threshold, a few
levels, the colors of a [palette](palettes.md), or levels chosen by a
threshold map, which gives the [hybrid with ordered
dithering](ordered-dithering.md#with-error-diffusion-the-hybrid). Any
kernel works with any quantizer, and inside the cells of [machine
screens](machine-screens/README.md).

With a gamma (`--gamma` in the CLI, `ditherImageWith` in the library;
see [gamma.md](gamma.md)), the error is measured in the curve's light:
`corrected` and `q` are amounts of light, so the tones kept are the
light's, not the stored numbers' average. The nearest allowed value is
still chosen on stored values, and the output is exactly the allowed
values.

## The kernels

| Kernel | Library | CLI | Neighbours | Rows below | Error passed on |
|---|---|---|---:|---:|---|
| Floyd–Steinberg | `floydSteinberg` | `floyd-steinberg` | 4 | 1 | all |
| Atkinson | `atkinson` | `atkinson` | 6 | 2 | 3/4 |
| Jarvis–Judice–Ninke | `jarvisJudiceNinke` | `jjn` | 12 | 2 | all |
| Stucki | `stucki` | `stucki` | 12 | 2 | all |
| Burkes | `burkes` | `burkes` | 7 | 1 | all |
| Sierra 3 | `sierra3` | `sierra-3` | 10 | 2 | all |
| Sierra 2 | `sierra2` | `sierra-2` | 7 | 1 | all |
| Sierra Lite | `sierraLite` | `sierra-lite` | 3 | 1 | all |
| Fan | `fan` | `fan` | 4 | 1 | all |
| Shiau–Fan | `shiauFan` | `shiau-fan` | 4 | 1 | all |
| Shiau–Fan 2 | `shiauFan2` | `shiau-fan-2` | 5 | 1 | all |
| none | `noDiffusion` | `none` | 0 | 0 | none |

Each table below is as published: `X` is the current pixel, the numbers
are the weights' numerators, and the divisor is on the right. The
library's offsets are read off the table: `dx` columns to the right of
`X` (negative to the left), `dy` rows down. Floyd–Steinberg's first
offset, for example, is `{ dx: 1, dy: 0, weight: 7.0 / 16.0 }`.

What each kernel is good for is quoted or paraphrased from its sources,
named with it. Notes marked *seen here* are this project's own
observations, on its [test images](test-images.md); beyond them, the
kernels haven't been compared with each other here yet.

*Seen here,* with every kernel that passes on all the error: a small
palette gets dots of other hues where it lacks the picture's colors.
With `ansi16`, about 1% of the test image's red sphere comes out green.
Atkinson, which drops a quarter of the error, shows none there.

### Floyd–Steinberg

```
    X   7
3   5   1            ÷ 16
```

Robert W. Floyd and Louis Steinberg, 1976. The classic, and the CLI's
default (except with `--bayer`, where the default is no diffusion).
Wikipedia: it "only diffuses the error to neighboring pixels. This
results in very fine-grained dithering." *Seen here:* at tones very near
black or white, the dots line up into curved diagonal strings, "worms",
and the first dots appear only after a dot-free strip (the
[`gray:shadows-highlights`](test-images.md#grayshadows-highlights) tile).
With [serpentine scanning](#serpentine-scanning), the worms are gone; the
strip stays.

Source: R. W. Floyd and L. Steinberg, "An adaptive algorithm for spatial
grey scale", Proceedings of the Society for Information Display 17
(1976), 75–77; DitherPunk.jl cites a version in the SID's 1975 symposium
digest, 36–37.

### Atkinson

```
    X   1   1
1   1   1
    1                ÷ 8
```

Bill Atkinson, at Apple; used in the original Macintosh (Wikipedia). Its
six neighbours get an eighth each, so only 3/4 of the error is passed on.
Wikipedia: "a more localized dither, at the cost of lower performance on
near-white and near-black areas, but the increase in contrast on those
areas may be regarded as more visually desirable for some purposes."
Helland: "By only propagating part of the error, speckling is reduced, but
contiguous dark or bright sections of an image may become washed out."
*Seen here:* tones near black and white are pushed to them; on the
machine screens, the shadow side of the test images' sphere turns solid
black ([machine-screens/](machine-screens/README.md)). Under a gamma, the
dropped quarter costs more of the dark tones: to black and white, flat
grays up to 32 come out solid black with `off`, up to 65 with `srgb`
([dark tones](gamma.md#dark-tones)).

Sources: Wikipedia, "Atkinson dithering" and "Dither"; Helland.

### Jarvis–Judice–Ninke

```
        X   7   5
3   5   7   5   3
1   3   5   3   1    ÷ 48
```

J. F. Jarvis, C. N. Judice and W. H. Ninke, 1976; Wikipedia calls it
"minimized average error dithering". Wikipedia: it "diffuses the error
also to pixels one step further away. The dithering is coarser but has
fewer visual artifacts." With 12 neighbours, it's the slowest of the
kernels measured here.

Source: J. F. Jarvis, C. N. Judice and W. H. Ninke, ["A survey of
techniques for the display of continuous tone pictures on bilevel
displays"](https://doi.org/10.1016/S0146-664X(76)80003-2), Computer
Graphics and Image Processing 5 (1976), 13–40.

### Stucki

```
        X   8   4
2   4   8   4   2
1   2   4   2   1    ÷ 42
```

Peter Stucki, IBM Zurich, 1981: Jarvis–Judice–Ninke's 12 neighbours with
other weights. Helland: "for most images, there will be minimal difference
between the output of Stucki and JJN algorithms"; Wikipedia: "Its output
tends to be clean and sharp." Both also call it faster than
Jarvis–Judice–Ninke: its weights are powers of two, so after the division
by 42 a program working in whole numbers can shift bits instead of
multiplying. puregrain works in floating point, so that doesn't apply
here: Stucki has as many neighbours as Jarvis–Judice–Ninke.

Source: P. Stucki, "MECCA – a multiple-error correcting computation
algorithm for bilevel image hardcopy reproduction", Research Report
RZ1060, IBM Research Laboratory, Zurich, 1981 (as cited by DitherPunk.jl);
the table in Helland and DitherPunk.jl.

### Burkes

```
        X   8   4
2   4   8   4   2    ÷ 32
```

Daniel Burkes, 1988: Stucki without its last row. Helland: with its
divisor of 32, all the arithmetic can be done by shifting bits, "with only
a minor hit to quality". Wikipedia: "a simplified form of Stucki dithering
that is faster, but is less clean than Stucki dithering." Here it has 7
neighbours instead of 12.

Source: D. Burkes, "Presentation of the Burkes error filter for use in
preparing continuous-tone images for presentation on bi-level devices",
unpublished, 1988 (as cited by DitherPunk.jl); the table in Helland and in
DitherPunk.jl's code (its doc comment shows Stucki's table instead).

### Sierra 3

```
        X   5   3
2   4   5   4   2
    2   3   2        ÷ 32
```

One of three kernels that Frankie Sierra published in 1989 and 1990
(Helland), with Sierra 2 and Sierra Lite. Also called
"Sierra" (Helland, Wikipedia), "Sierra-3" (Helland), "three-row Sierra"
(DitherPunk.jl), and `sierra3` in FFmpeg. puregrain uses the numbered
names, which say how many rows each one spans. Wikipedia: it "is based on
Jarvis dithering, but it is faster while giving similar results" (marked
there as needing a benchmark). Here: 10 neighbours, two fewer than
Jarvis–Judice–Ninke.

Sources: Helland; DitherPunk.jl.

### Sierra 2

```
        X   4   3
1   2   3   2   1    ÷ 16
```

Also called "two-row Sierra" (Helland, Wikipedia), "Sierra2"
(DitherPunk.jl), and `sierra2` in FFmpeg. Wikipedia: Sierra 3 "modified
by Sierra to improve its speed". Here: 7 neighbours.

Sources: Helland; DitherPunk.jl.

### Sierra Lite

```
    X   2
1   1                ÷ 4
```

Also called "Sierra Filter Lite" (Wikipedia), "Sierra-2-4A"
(DitherPunk.jl), and `sierra2_4a` in FFmpeg, where it's the default.
Wikipedia: "much simpler and faster than Floyd–Steinberg, while still
yielding similar results" (the speed is marked there as needing a
source); the libcaca study: "one of the simplest Floyd–Steinberg
derivatives". Here: 3 neighbours, one fewer than Floyd–Steinberg.

Sources: Helland; DitherPunk.jl; the libcaca study.

### Fan

```
        X   7
1   3   5            ÷ 16
```

Zhigang Fan, 1993: Floyd–Steinberg's weights with one moved, its 1/16
from below-right to two columns left. The libcaca study: it "just moves
one coefficient around". The two kernels below are by the same author,
with Jeng-Nan Shiau.

Source: Z. Fan, "A simple modification of error diffusion weights",
IS&T's 46th Annual Conference, 1993, 113–115 (as cited by DitherPunk.jl);
the table in DitherPunk.jl and ditherit.com's code.

### Shiau–Fan

```
        X   4
1   1   2            ÷ 8
```

Jeng-Nan Shiau and Zhigang Fan, 1993: weights in eighths, made to reduce
the "worm" artifacts of Floyd–Steinberg. Their 1996 paper's title says
both: "Set of easily implementable coefficients in error diffusion with
reduced worm artifacts".

Sources: [US patent 5,353,127](https://patents.google.com/patent/US5353127A/en),
claim 2 (Shiau and Fan, Xerox; filed 1993-12-15, granted 1994-10-04);
J. N. Shiau and Z. Fan, [the paper
above](https://doi.org/10.1117/12.236968), Proc. SPIE 2658 (1996),
222–225; the table also in DitherPunk.jl and ditherit.com's code.

### Shiau–Fan 2

```
            X   8
1   1   2   4        ÷ 16
```

The same aim, with one more neighbour, three columns to the left.

Sources: US patent 5,353,127, claim 4; DitherPunk.jl; ditherit.com's
code.

## Serpentine scanning

Every row is scanned left to right by default. With serpentine scanning,
`withScan serpentine` in the library and `--serpentine` in the CLI, the
rows alternate: the first left to right, the second right to left, and so
on. On a row scanned right to left the kernel is mirrored, so the error
still goes to pixels not yet processed: `dx` columns to the left instead
of the right. Wikipedia: "In some implementations, the horizontal
direction of scan alternates between lines; this is called 'serpentine
scanning'" ("Floyd–Steinberg dithering"), one of the refinements "to
reduce more artifacts" ("Error diffusion").

*Seen here,* with Floyd–Steinberg on the
[`gray:shadows-highlights`](test-images.md#grayshadows-highlights) tile at
256 × 256: the worms are gone. With every row left to right, the dots near
black and near white line up in chains that lean one way: of the pairs of
dots one row apart and one to three columns apart, 74% near black and 82%
near white have the lower dot to the left. With serpentine scanning, 46%
and 51%: the dots spread evenly, and fewer sit close together (547 and 518
such pairs, against 796 and 762), with the same number of dots, so the same
tone. What stays: the dot-free strip before the first dots, and on
[`gray:vramp`](test-images.md#grayvramp) the row of dots where they begin;
both come from error building up, which the scan's direction doesn't
change. On a [machine's screen](machine-screens/README.md), the thin
streaks Floyd–Steinberg leaves in the cells stay too: they come from error
a cell can't use, which serpentine scanning still passes on.

It works with every kernel and quantizer, ordered dithering's hybrid and
machine screens included; each pixel's quantizer still gets its own
position, counted from the image's left edge. With no diffusion it changes
nothing, and the CLI rejects it there. It costs nothing measurable: at
1024 × 1024, ×1.00 in the median over the configurations measured, by
each round's pair ([benchmarks](benchmarks-dithering.md), 2026-11-23). It
isn't the default, so that a picture dithered before comes out as it did.

## Your own kernel

`fromOffsets` builds a kernel from a list of offsets, and checks it:

```purescript
import Puregrain.Kernel (fromOffsets)

-- Floyd–Steinberg written out: gives Right floydSteinberg
myKernel = fromOffsets
  [ { dx: 1,  dy: 0, weight: 7.0 / 16.0 }
  , { dx: -1, dy: 1, weight: 3.0 / 16.0 }
  , { dx: 0,  dy: 1, weight: 5.0 / 16.0 }
  , { dx: 1,  dy: 1, weight: 1.0 / 16.0 }
  ]
```

A `Left` says which offset breaks which rule:

- every offset must point forward: to a later row (`dy > 0`), or further
  right in the same row (`dy = 0`, `dx > 0`);
- every weight must be a finite number;
- no two offsets may point to the same neighbour.

The sum of the weights isn't checked: below 1, part of the error is
dropped, as in Atkinson's; above 1, it's amplified. A kernel may reach as
far as you like; time grows with its number of neighbours. Your own
kernels work in the library only: the CLI takes the names above.

## Not included

- **False Floyd–Steinberg** (3/8 right, 3/8 below, 2/8 below-right): a
  simplification that "not only produces markedly worse output but it
  does so without any conceivable advantage in terms of speed" (Helland),
  and its name confuses. For a cheap kernel, use Sierra Lite.
- **Simple 2D** (half the error right, half down): an example for
  teaching; Floyd–Steinberg costs about the same.
- **Stevenson–Arce:** made for pixels on a hexagonal grid ("for hexagonal
  cells", the libcaca study); on square pixels, it isn't the filter its
  authors tuned.

Any of them can be built with `fromOffsets`.

## Exact properties

- **An image made only of allowed values comes back unchanged,** with any
  kernel, under every gamma: its error is zero everywhere. Tested for
  arbitrary kernels in `Test.Puregrain.PaletteSpec`, and under each curve
  in `Test.Puregrain.InLightSpec`; through the CLI with every kernel, and
  with two under each curve (`npm run check:cli`, see
  [test-images.md](test-images.md#exact-checks)).
- **The diffusion is checked against an independent reference,** a
  deliberately simple implementation, for random kernels and images, with
  every row left to right and with serpentine scanning, which the
  reference writes out on its own (`Test.Puregrain.DiffusionMechanicsSpec`).
- **Every preset's offsets and weights equal its published table,**
  written out in `Test.Puregrain.KernelSpec` independently of the library.

## References

- R. W. Floyd and L. Steinberg, "An adaptive algorithm for spatial grey
  scale", Proceedings of the SID 17 (1976), 75–77.
- J. F. Jarvis, C. N. Judice and W. H. Ninke, ["A survey of techniques for
  the display of continuous tone pictures on bilevel
  displays"](https://doi.org/10.1016/S0146-664X(76)80003-2), Computer
  Graphics and Image Processing 5 (1976), 13–40.
- [US patent 5,353,127](https://patents.google.com/patent/US5353127A/en),
  J. N. Shiau and Z. Fan (Xerox): the weights of Shiau–Fan (claim 2) and
  Shiau–Fan 2 (claim 4).
- Tanner Helland, ["Image Dithering: Eleven Algorithms and Source
  Code"](https://tannerhelland.com/2012/12/28/dithering-eleven-algorithms-source-code.html)
  (2012): the tables of Stucki, Burkes and the three Sierras, their
  history, and False Floyd–Steinberg.
- [DitherPunk.jl's `error_diffusion.jl`](https://github.com/JuliaImages/DitherPunk.jl/blob/a8b3a623cc145fecb88c95212306cf0641710dd8/src/error_diffusion.jl):
  every kernel here as code, most with references to the original
  publications.
- Sam Hocevar, [the libcaca study, part 3](http://caca.zoy.org/study/part3.html):
  error diffusion and its kernels, Fan's and Shiau–Fan's among them.
- Wikipedia: ["Dither"](https://en.wikipedia.org/wiki/Dither) (each
  classic kernel in a sentence), ["Atkinson
  dithering"](https://en.wikipedia.org/wiki/Atkinson_dithering), and
  ["Floyd–Steinberg dithering"](https://en.wikipedia.org/wiki/Floyd%E2%80%93Steinberg_dithering)
  and ["Error diffusion"](https://en.wikipedia.org/wiki/Error_diffusion)
  (serpentine scanning, 2026-11-23).
- FFmpeg's [`paletteuse` filter](https://ffmpeg.org/ffmpeg-filters.html#paletteuse):
  the names `sierra3`, `sierra2` and `sierra2_4a`, its default.
- [ditherit.com](https://ditherit.com): its kernels, read from the page's
  script (2026-11-03), agree with the tables of Fan, Shiau–Fan and
  Shiau–Fan 2.
