# Gamma: dithering that keeps the light

A picture stores numbers, and a screen turns them into light, but not in
proportion: the stored gray 128, halfway between black and white, gives
off only about a fifth of white's light on a screen. Dithering mixes dots
of a few colors, and the eye averages the dots' *light*. So dithering
that keeps the average of the stored numbers, as it traditionally does,
can come out lighter than the picture, and dithering that keeps the
light comes out right, but only where the dots reach the eye as they are.

puregrain's **gamma** says which of the two to keep. It doesn't adjust
the picture, as an image editor's gamma slider does: it says how the
screen turns the numbers into light, and the dithering then keeps that
light. The default, **off**, keeps the stored numbers, as dithering always
has.

The option is the same everywhere: `--gamma` in the
[command-line tool](../cli/README.md), "Gamma" in the
[web UI](../web/README.md), and a `Gamma` argument in the library.

## In short

| Where the picture is seen | Gamma |
|---|---|
| Scaled down, on a phone or a HiDPI screen, fitted into a page, or not known | `off` (the default) |
| At 100%, one dot per screen pixel, from a distance | `srgb` |
| Both, or neither for sure | `1.5`, the compromise |
| On a machine's screen (ZX Spectrum, C64) | `off` |
| With Atkinson | `off` (see [Dark tones](#dark-tones)) |

Try them on your own pictures, and look at them the way they'll be
seen: what's right depends on the view more than on the picture.

## The five values

- **`off`** (the default; `1.0` and `1` mean the same): no conversion.
  The dithering keeps the average of the stored numbers, as it always
  has, and gives exactly the same results as before gamma existed.
- **`srgb`:** the sRGB standard's own curve (IEC 61966-2-1), a straight
  piece near black and a power of 2.4 above it, which behaves much like a
  power of 2.2 overall. The dithering keeps the light; this is "linear
  light". The strongest.
- **`1.2`, `1.5` and `1.8`:** power curves, light = (value / 255)^γ,
  between `off` and `srgb`.

How much changes, with gray 128 dithered to black and white by
Floyd–Steinberg: with `off` about 50% of the dots are white, the average
of the numbers; with `srgb` about 21.6%, gray 128's share of white's
light.

What works in light and what doesn't:

- **The error** that error diffusion passes on, and **where an ordered
  pattern places its dots**, are amounts of light, measured in the
  curve's light.
- **The nearest level or palette color** is still chosen on the stored
  numbers, which match how different colors look better than light does.
- **Levels and thresholds stay what you'd type:** `--threshold 100` cuts
  at the stored gray 100 under every gamma, and `--levels 4` means the
  bytes 0, 85, 170 and 255. Levels that aren't whole numbers, such as 3
  levels' 127.5, are rounded under a curve, so that each level comes back
  as exactly its byte.
- **The output** is always exactly the levels', the palette's or the
  machine's own colors.

**Every picture counts as sRGB.** Neither the command-line tool nor the
web UI reads a picture's color profile: both dither the stored numbers.
A Display P3 picture, which uses sRGB's curve, gets its light right with
`srgb`; Adobe RGB and Apple RGB pictures come out a little off.

## Which value for which view

The eye averages light, but only if the dots reach it as they are. On a
phone, a HiDPI screen, or wherever a picture is scaled to fit, the
viewer smooths it first, and smoothing averages the stored numbers. Then
the stored average is what's shown, and `off` is the exact choice.

Measured on the gray test image (the [test images](test-images.md),
512 × 512) dithered to black and white: each result blurred as the eye
blends dots from a distance, then compared with the original, blurred
the same way. The error is in CIE L* (100 is the step from black to
white; a step of about 1 is just visible), and the blur averages either
the dots' light or their stored numbers:

| Gamma | Floyd–Steinberg: blurred in light | Floyd–Steinberg: blurred as stored | Light given off (original: 37.8%) | Mean stored value (original: 135.5) |
|---|---:|---:|---:|---:|
| `off` | 18.0 | 1.5 | 53.2% | 135.5 |
| `1.2` | 14.1 | 4.7 | 49.5% | 126.3 |
| `1.5` | 9.2 | 10.0 | 45.2% | 115.2 |
| `1.8` | 5.5 | 14.2 | 41.7% | 106.4 |
| `srgb` | 3.8 | 18.9 | 37.9% | 96.7 |

- **`off`** keeps the stored average exactly, and gives off far too much
  light: at 100%, the picture looks too light.
- **`srgb`** gives off exactly the original's light, but its stored
  numbers average 39 steps too dark: scaled by a smoothing viewer, the
  picture looks too dark.
- **`1.5`** keeps the larger of the two errors smallest, for every
  method measured (Floyd–Steinberg, Atkinson, Bayer 2 and 4, and 4 levels,
  in gray and in color). Seen in both ways, it's never far off.

## Dark tones

The higher the gamma, the more of the darkest grays turn black, in the
file itself, so on any screen. A dark gray's light is a tiny share of
white's, and a Bayer map, or Atkinson, which passes on only ¾ of each
error, can't place a single white dot for it. The largest flat gray that
still comes out all black:

| Gamma | Half the light at byte | Bayer 2 | Bayer 4 | Atkinson |
|---|---:|---:|---:|---:|
| `off` | 127.5 | 31 | 7 | 32 |
| `1.2` | 143.1 | 45 | 14 | 40 |
| `1.5` | 160.6 | 63 | 25 | 50 |
| `1.8` | 173.5 | 80 | 37 | 59 |
| `srgb` | 187.5 | 99 | 49 | 65 |

Floyd–Steinberg, and every kernel but Atkinson, loses none at any gamma:
they pass all the error on, so every gray above 0 gets its dots. That's
why the table above recommends `off` with Atkinson: its dropped error is
a trick made for stored numbers.

## Gray first

`--gray` (in the web UI, "Turn the picture gray first") turns a color
picture gray before dithering, and the gamma decides how:

- **`off`:** Rec. 601 luma, 0.299 R + 0.587 G + 0.114 B on the stored
  numbers, the classic conversion, as before.
- **Any curve:** the gray that gives off as much light as the color,
  0.2126 R + 0.7152 G + 0.0722 B on the channels' light (luminance, with
  `srgb`). Saturated colors come out lighter than with luma: pure blue is
  76 instead of 29, pure red 127 instead of 76. Natural colors, such as
  skin and sky, barely change.

A neutral pixel stays exactly as it is, under every gamma.

## Machine screens

On a ZX Spectrum's or a C64's screen, each cell has only two colors, and
that limit decides most of how close the result comes, under any gamma.
The cells are chosen on the stored numbers, as before; a curve only
changes how the dots are placed between each cell's two colors. Measured
on the test image at each screen's size: a curve brings the result up to
31% closer to the original seen at 100% on a ZX Spectrum, but only 4% to
6% on a C64, and makes it 17% to 96% worse when the screen is scaled.
With Bayer 2 under `srgb`, the dark tones of a ZX Spectrum picture turn
black, the shadow side of the test image's sphere included.

So: `off` for machine screens, the look of the time, with the dark tones
exact. `1.5` or `srgb` with Bayer 4 is something to try for a picture
seen at 100%. How the screens work: [machine-screens/](machine-screens/README.md).

## In the command-line tool

```bash
npm run dither-cli -- photo.png out.png --levels 4 --kernel atkinson --gamma 1.5
npm run dither-cli -- photo.png out.png --threshold 128 --gamma srgb
npm run dither-cli -- --check-engine
```

`--gamma` combines with every other option. The line the tool prints
after dithering names the gamma when it isn't `off`. `--check-engine`
runs the engine check (below), and exits with 1 if it fails. All the
options: [cli/README.md](../cli/README.md).

## In the web UI

"Gamma", in step 4, Method: Off, 1.2, 1.5, 1.8 and sRGB. A note under it
says when it can't change the picture: without colors chosen, or without
a method that spreads light (an error diffusion or a Bayer map). With a
gamma other than Off, the page also puts a transparent picture onto its
background, and fits a picture to a machine's screen, in the curve's
light, so every step that mixes colors keeps the same light. The icon
left of Help shows the engine check's result. More:
[web/README.md](../web/README.md).

## In the library

The presets are in `Puregrain.Gamma`, and in the `Puregrain` facade:
`gammaOff`, `gamma1p2`, `gamma1p5`, `gamma1p8` and `gammaSrgb` ("p" for
the point). Each driver has a twin that takes a gamma first; the plain
drivers are the twins with `gammaOff`:

```purescript
import Puregrain as P

P.ditherImageWith P.gammaSrgb P.floydSteinberg (P.threshold 128.0) image
P.ditherRowsWith P.gamma1p5 P.atkinson (P.perChannel (P.nearestLevel (P.evenRamp 4))) rows
P.initDitheringWith P.gammaSrgb P.floydSteinberg quantizer   -- the stepper

-- a color picture turned gray, as --gray does
P.ditherImageWith gamma P.floydSteinberg (P.threshold 128.0) (map (map (P.toGray gamma)) image)
```

`Puregrain.Cells` has `ditherCellsWith` and `ditherBandsWith`, the same
for machine screens. `Puregrain.Gamma.toLight` and `fromLight` convert a
pixel's color channels (alpha stays as it is).

**Writing your own quantizer.** The ready-made ones work in light. To
build one that does, use `Puregrain.Quantize.quantizeInLight`, which
hands you the dithering's curve first. Convert your numbers in the outer
`let`, once per picture, and return the function for each pixel, which
gets and returns light:

```purescript
-- three tones: black, a mid gray, and white
threeTones = quantizeInLight \gamma ->
  let lo = toLight gamma 64.0
      hi = toLight gamma 192.0
      gray = toLight gamma 128.0
  in \_ v -> if v < lo then 0.0 else if v < hi then gray else 255.0
```

Inside the inner function, the conversions would run for every pixel:
PureScript shares nothing by itself. An output that is the light of a
whole number from 0 to 255 is written as exactly that number. Two more
cases:

- **Numbers kept as they are:** a quantizer that ignores the curve it's
  handed takes its numbers as light under any curve but `gammaOff`. Then
  what's written comes back through the curve's formula, and is exact
  only where the numbers are the light of whole bytes.
- **Numbers made for one curve, used with another:** convert them once,
  in the outer `let`, with `fromLight` of the one and `toLight` of the
  other.

`quantize` and `quantizeWith` still work under a curve: your function
keeps seeing stored values, converted for it both ways for each pixel,
which costs more. `runQuantizeWith` runs a quantizer as the twins do,
for a stored value.

## Exact on every engine

The curves are computed from the operations that JavaScript defines
exactly (addition, multiplication, division, the square root) and roots
of our own, so every correct engine gives the same bits: the command-line
tool and the web UI, in every browser, give the same results. The light
of every whole number from 0 to 255 comes back exactly. Why and how:
[exact-arithmetic.md](exact-arithmetic.md).

The **engine check** makes sure on the engine at hand: it computes the
curves for a fixed set of values and compares a digest of the results
with the reference. `--check-engine` in the command-line tool, the icon
in the web UI, and `Puregrain.SelfCheck.checkEngine` in the library. A
pass means this engine computed the reference values exactly: strong
evidence, checked rather than guaranteed. With `off`, nothing it covers
is used.

## What it costs

With `srgb`, dithering takes about a third longer at 1024 × 1024 than with
`off`: Floyd–Steinberg with a threshold ×1.2, levels per channel about
the same, a palette ×1.4 to ×2.0, since each pixel is brought back from
light for the search. With `off`, nothing changes. The numbers:
[benchmarks-dithering.md](benchmarks-dithering.md#2026-11-15--what-a-gamma-costs-linear-light).

## Not yet

- **Color profiles:** pictures in other color spaces aren't converted
  (see "Every picture counts as sRGB" above); a later step.
- **Perceptual color distances** (CIELAB, OKLab), for choosing the
  nearest palette color, would build on the same light; also later.
