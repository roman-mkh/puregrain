# Palettes

Ready-made fixed palettes for dithering to a limited set of colors. With a
palette, each pixel becomes the **nearest palette color, choosing all
three channels together**. This project calls that *vectorED*, as
opposed to dithering each channel on its own with `--levels` (*scalarED*).

In the library they're plain `NonEmptyArray RGB` values in
`Dither.Palette.Presets`. On the command line you name them with
`--palette NAME` (see [cli/README.md](../cli/README.md)).

## Overview

| Preset | CLI name | Colors | What it is | Source of the values |
|---|---|---:|---|---|
| `blackWhite` | `bw` | 2 | Black and white | — |
| `websafe216` | `websafe216` | 216 | The web-safe colors | Defined by a formula (below) |
| `cga16` | `cga16` | 16 | IBM PC: CGA's colors, EGA's and VGA's defaults, the DOS/Linux console | [Wikipedia: Color Graphics Adapter](https://en.wikipedia.org/wiki/Color_Graphics_Adapter) |
| `ansi16` | `ansi16` | 16 | The ANSI terminal colors, as xterm's defaults | xterm's [XTerm-col.ad](https://raw.githubusercontent.com/ThomasDickey/xterm-snapshots/master/XTerm-col.ad); matches [Wikipedia: ANSI escape code](https://en.wikipedia.org/wiki/ANSI_escape_code) |
| `ansi256` | `ansi256` | 256 (249 distinct) | xterm's 256 colors | xterm's [256colres.pl](https://raw.githubusercontent.com/ThomasDickey/xterm-snapshots/master/256colres.pl) |
| `c64` | `c64` | 16 | Commodore 64 | [Pepto's 2001 palette](https://www.pepto.de/projects/colorvic/2001/) |
| `zxSpectrum` | `zx-spectrum` | 15 | ZX Spectrum, normal and bright | [lospec](https://lospec.com/palette-list/zx-spectrum), from the 85% rule in [Wikipedia: ZX Spectrum graphic modes](https://en.wikipedia.org/wiki/ZX_Spectrum_graphic_modes) |

Old computers had analog video, and terminals let users change their
colors, so most of these palettes have **no single official set of RGB
values**. Each preset here uses one well-known, cited version; the
values were checked against those sources, and the tests pin them.

**Order matters in one case:** when a pixel is exactly as near to two
palette colors, the one listed first wins.

## Using a preset

In the library, a palette becomes a quantizer with `nearestColor`, which
is passed to `ditherImage` like any other quantizer:

```purescript
import Dither.Palette (nearestColor)
import Dither.Palette.Presets (c64)

quantizer = nearestColor c64   -- :: Quantize RGB
```

`nearestColor` compares colors by plain RGB distance. To choose the
distance measure yourself, use `compilePalette distance2 c64` with
`nearestColorFast`.

On the command line:

```bash
npm run dither-cli -- samples/color-512.png samples/c64.png --palette c64
```

(The library's module names will change before the first release; see
the [README](../README.md).)

## Equivalences worth knowing

Some palettes are a complete grid of per-channel values. For those, the
nearest palette color is exactly the nearest value in each channel
separately, so per-channel levels give the **same result**, a little
faster:

| This palette | gives exactly the same result as | because |
|---|---|---|
| `websafe216` | `--levels 6` (`perChannel (nearestLevel (evenRamp 6))`) | its 216 colors are every combination of 0, 51, 102, 153, 204, 255 |
| EGA's full 64 colors (no preset needed) | `--levels 4` | EGA's 64 colors are every combination of 0, 85, 170, 255 |

For `websafe216` the equivalence is tested byte for byte (see [Exact
checks](test-images.md#exact-checks)). The palette search took about
1.1–1.4× as long as the per-channel lookup
([benchmarks](benchmarks-dithering.md)).

`ansi256` *contains* a grid (its 6×6×6 cube), but it also has 16 theme
colors and 24 grays, so it isn't one, and needs the full palette search.

## Notes on each palette

### `blackWhite` (`bw`)

Black, then white. Each pixel becomes whichever is nearer **in RGB**,
which isn't the same as brightness. Pure green `(0, 255, 0)` looks bright,
yet it's nearer to black (distance² 255² against 2·255²), so saturated
colors can come out darker than expected. To go by brightness, convert
to gray first (`--gray`, or the default `--threshold` mode). On a gray
image, `bw` makes the same decisions as a threshold at 127.5, with an
exact tie at 127.5 going to black.

### `websafe216`

The 216 "web-safe" colors: every combination of 0, 51, 102, 153, 204 and
255, with red varying slowest, so the list starts at black and ends at
white. See the equivalence with `--levels 6` above.

### `cga16`

The IBM PC's 16 colors, in index order 0–15. CGA built them from four
bits, "RGBI": each set red, green or blue bit gives that channel `0xAA`,
and the intensity bit adds `0x55` to all three. IBM's monitor made one
exception, turning color 6 from dark yellow into brown (`#AA5500`).

The same 16 colors are EGA's and VGA's defaults and the DOS text-mode
colors. VGA stores 6 bits per channel, so some tables write `A8` instead
of `AA`. The Linux text console uses exactly these 16 values too
(`drivers/tty/vt/vt.c` in the kernel), but in ANSI order, where 1 is red
and 4 is blue, the reverse of CGA's 1 blue and 4 red.

Not every "CGA/EGA/VGA" table agrees. Wikipedia's comparison of terminal
colors
([ANSI escape code](https://en.wikipedia.org/wiki/ANSI_escape_code))
has a column of that name with different numbers, such as red 196
instead of 170 and dark gray 78 instead of 85, apparently adjusted for
how the colors looked on screen. This preset uses the digital values,
as the CGA article and the Linux kernel do.

### `ansi16`

The 16 terminal colors in index order: black, red, green, yellow, blue,
magenta, cyan, white, then the bright versions. The ANSI standard names
these colors but defines no RGB values, and every terminal shows them
differently. This preset uses xterm's defaults, which are X11 color
names: red3 `(205, 0, 0)`, blue2 `(0, 0, 238)`, gray90, gray50, and so on;
bright blue is `(92, 92, 255)`. For the Linux console's colors, use
`cga16`: the same values, in a different order.

### `ansi256`

xterm's 256-color palette:

| Indices | What | Values |
|---|---|---|
| 0–15 | the 16 terminal colors (`ansi16`) | follow the terminal's theme in real terminals |
| 16–231 | a 6×6×6 color cube, index 16 + 36r + 6g + b | each channel one of 0, 95, 135, 175, 215, 255 |
| 232–255 | 24 grays | 8, 18, 28, …, 238 |

Seven colors appear twice: the cube repeats black, white, and the bright
red, green, yellow, magenta and cyan (xterm's bright blue isn't in the
cube). That leaves 249 distinct colors.

### `c64`

The Commodore 64's 16 colors in VIC-II index order: black, white, red,
cyan, purple, green, blue, yellow, orange, brown, light red, dark grey,
grey, light green, light blue, light grey. There's no official RGB
definition. These are Pepto's calculated PAL values (2001, gamma
corrected), the usual reference.

### `zxSpectrum` (`zx-spectrum`)

The ZX Spectrum's 8 colors (black, blue, red, magenta, green, cyan,
yellow, white) at normal brightness, then the 7 non-black ones at
BRIGHT, since bright black is just black: 15 colors. The real colors
were never measured. This preset uses the common model of normal = 85%
of bright: `0xD8` against `0xFF`. Many emulators use `0xD7` or `0xCD`
instead.

It gives each pixel a Spectrum color, but **not the real Spectrum
look**. The machine allowed only 2 colors in each 8×8 block, which
per-pixel dithering doesn't imitate (see below).

## Not included (yet)

- **Other terminal themes** (Windows' Campbell, Solarized, …): user
  choices rather than standards. Pass your own palette instead:
  `nearestColor` takes any non-empty array of colors.
- **Block-restricted looks:** the real ZX Spectrum (2 colors per 8×8
  block), C64 multicolor modes, and pseudo-graphics from block characters
  (ANSI/Unicode blocks, PETSCII, teletext). These choose colors per
  block, not per pixel, which is a different kind of algorithm. It's
  listed as a future extension in [TODO.md](../TODO.md).
- **A perceptual distance measure** (CIELAB): planned as `distance2Lab`
  ([TODO.md](../TODO.md)). Until then, all palettes are matched by plain
  RGB distance.
