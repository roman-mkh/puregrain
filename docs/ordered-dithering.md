# Ordered dithering

Ordered dithering decides each pixel against a threshold that depends on
the pixel's position. The thresholds come from a small matrix, a
*threshold map*, repeated across the image like tiles. The best known one
is the Bayer matrix, after Bryce E. Bayer (Kodak, 1973).

puregrain has it in the library (`Dither.Ordered`) and in the CLI
(`--bayer N`, see [cli/README.md](../cli/README.md#ordered-dithering)). It
works on its own, or combined with any error-diffusion kernel.

## The idea

Error diffusion compares every pixel against the same threshold and makes
up for each pixel's error with its neighbours. Ordered dithering passes no
error on. Instead, neighbouring pixels get different thresholds, so a flat
gray area turns on exactly the cells whose threshold is below its value.
The matrix decides in which order the cells turn on as the input rises.

The result is a regular texture: the same pattern for the same gray, in
every tile, from the first pixel on. Each pixel is decided on its own, so
nothing builds up, nothing flows across region borders, and there are no
"worms". It's also fast: about a third of Floyd–Steinberg's time
([benchmarks](benchmarks-dithering.md#2026-10-04--ordered-dithering-bayer)).

## Thresholds

For two levels, 0 and 255 (1-bit):

```
t(x, y) = (M[y mod n][x mod n] + 0.5) / n²       (between 0 and 1)
output  = 255  if v / 255 > t(x, y),  else 0
```

`M` is the n × n matrix of ranks 0 … n² − 1. The `+ 0.5` puts each
threshold in the middle of its step, so a flat area of value `v` turns on
the cells with `(rank + 0.5) / n² < v / 255`.

**For more levels**, the same rule applies between the two levels around
the value. For `lo ≤ v < hi`:

```
output = hi  if (v − lo) / (hi − lo) > t(x, y),  else lo
```

A value that is exactly a level stays that level, and values below the
lowest level or above the highest snap to it. Color is dithered per
channel: each channel of a pixel goes through the same rule, with the same
threshold.

**How many tones:** between two levels, an n × n map can show n² + 1
different patterns, from no cell on to all n² cells on: 5 for Bayer 2×2, 17
for 4×4, 65 for 8×8. Over a gray ramp they show as bands, one per pattern.

**Custom maps** (library only) give each cell a rank; the threshold is
`(rank + 0.5) / (maxRank + 1)`. A map needn't be square, and ranks may
repeat or skip values. That allows clustered-dot screens (dots grow from
the middle of each tile, as in print halftones) or blue-noise masks.
`compileThresholdMap` checks the ranks and says what's wrong if they don't
form a valid map.

## The Bayer matrix

The n × n Bayer matrix is built from the 1 × 1 matrix `[0]` by doubling:

```
M₂ₙ = | 4·Mₙ + 0   4·Mₙ + 2 |
      | 4·Mₙ + 3   4·Mₙ + 1 |
```

```
M₂ = 0 2        M₄ =  0  8  2 10
     3 1             12  4 14  6
                      3 11  1  9
                     15  7 13  5
```

It holds every rank from 0 to n² − 1 once, and cells with neighbouring
ranks lie far apart. So as the input rises, new dots appear spread over
the tile rather than in clumps: the patterns are as fine-grained as a
regular pattern can be.

The library builds any side that is a power of 2 (`bayer n` and the raw
ranks `bayerMatrix n`), including the trivial 1 × 1 map: one threshold of
0.5, so it just picks the nearer level. The CLI takes 2, 4, 8 or 16. With
8-bit input, 16 × 16 already has 256 thresholds, one per input level.

## With error diffusion: the hybrid

The threshold map only changes the quantizer, so it combines with any
kernel. Each pixel goes through the usual error-diffusion step, with the
position-dependent decision in the middle:

```
corrected = input(x, y) + error arriving from earlier pixels
q         = ordered decision on `corrected`, with t(x, y)
err       = corrected − q          (sent to the neighbours through the kernel)
```

The error is measured against the value, not against the threshold. So
error diffusion still keeps the average tone right, and the map only
decides where the dots land. The result shows the Bayer texture, broken up
wherever diffusion moves a dot; this is known as *threshold modulation*.
With the empty kernel (`--kernel none`), no error is passed on and it's
pure ordered dithering.

## What to look for

The [test images](test-images.md) show the differences. Look at 100%
zoom, as always.

| Tile | Pure ordered dithering (`--kernel none`) |
|---|---|
| [`gray:ramp`](test-images.md#grayramp) | The patterns in sequence: n² + 1 bands for n × n, where error diffusion gives smoothly changing density. |
| [`gray:wedges`](test-images.md#graywedges) | Each flat patch shows its exact pattern from its first pixel, even the narrow ones in the composite: there's no onset delay and no error from the neighbouring patches. |
| [`gray:shadows-highlights`](test-images.md#grayshadows-highlights) | No worms. Near black and white, a few regularly spaced dots instead. In the hybrid, the Bayer pattern breaks up Floyd–Steinberg's worms. |
| [`gray:zone-plate`](test-images.md#grayzone-plate), [`gray:lines`](test-images.md#graylines) | The weakness of any fixed pattern: moiré where it meets fine, regular detail. |
| [`color:channel-ramps`](test-images.md#colorchannel-ramps) | The patterns per channel. A gray area stays exactly gray, here and anywhere in the composite. |

## Exact properties

Tested on arbitrary input in `Test.Dither.OrderedSpec`; the last two also
run through the real CLI (`npm run check:cli`, see
[test-images.md](test-images.md#exact-checks)):

- Without diffusion, every n × n tile of a flat gray `g` has exactly as
  many white pixels as thresholds below `g / 255`.
- `bayer 1` is plain rounding to the nearest level: the same result as
  `nearestLevel`.
- Without diffusion, a neutral pixel (r = g = b) stays neutral, wherever it
  is in a color image.
- An image whose values are all levels comes back unchanged, with or
  without diffusion: the error is zero everywhere.

## Not supported

- **Ordered dithering against a palette.** The rule above needs levels in
  order, per channel; the colors of a palette like `cga16` or `c64` have no
  such order. Other methods exist, such as Joel Yliluoma's positional
  dithering algorithms, but none is implemented, so the CLI rejects
  `--bayer` with `--palette`. For palettes that are a grid of per-channel
  levels, use `--levels`: `--levels 6` gives exactly the web-safe colors,
  `--levels 4` EGA's 64, and `--levels 2` the 8 corners of the RGB cube.
- **Custom threshold maps in the CLI.** The library takes any map; the CLI
  only the Bayer sizes.

## References

- B. E. Bayer, "An optimum method for two-level rendition of
  continuous-tone pictures", IEEE International Conference on
  Communications, 1973.
- [Ordered dithering](https://en.wikipedia.org/wiki/Ordered_dithering) on
  Wikipedia: the threshold maps, and pointers to the palette methods.
