# Machine screens

Some 8-bit home computers couldn't color every pixel freely. Their screens
are divided into **cells**, and each cell may use only a few colors: on the
ZX Spectrum, two per 8×8 cell. puregrain dithers a picture to such a
screen, cell by cell, so the result is a picture the machine could really
show.

This page describes what all these screens share. Each machine has a page
of its own:

| Machine | Cells | Colors per cell | On the command line | Page |
|---|---|---|---|---|
| ZX Spectrum | 8×8 | 2 of 15: an ink and a paper, both normal or both bright | `--machine zx-spectrum` | [zx-spectrum.md](zx-spectrum.md) |

In the library, `Puregrain.Cells` dithers with cells of any size and any
candidate colors, and a `Puregrain.Machine.<Name>` module describes one
machine. On the command line, `--machine NAME` picks the machine (see
[cli/README.md](../../cli/README.md#machine-screens)).

## How it works

The picture is processed in **bands**, one row of cells at a time. In each
band:

1. **Every cell gets its colors.** Each candidate, one color or two, gets a
   score: the sum, over the cell's pixels in the original picture, of each
   pixel's squared distance (in r, g and b) to the nearest color the
   candidate can produce. For two colors, that's the nearest point on the
   straight line between them, since dithering can mix any share of the
   two; for one color, it's that color. The lowest score wins; on a tie,
   the candidate listed first. A middle gray, for example, fits black and
   white perfectly, but blue and white poorly.
2. **The band's pixels are dithered** with their cells' colors, by one of
   the two rules below, and the error-diffusion kernel passes each pixel's
   error on to its neighbours, across cell and band borders as usual.

The cells are chosen from the original picture, not from a dithered one,
so the choice doesn't depend on the kernel or the rule. Distances are
measured in the stored sRGB values, where the dithering mixes too.

## The two rules inside a cell

- **The nearer color** (`nearestInCell` in the library; the command
  line's default): each pixel becomes the nearer of its cell's two
  colors. With a kernel, that's error diffusion inside the cells; without
  one (`--kernel none`), flat cells.
- **Ordered** (`orderedInCell`; `--bayer N`): each pixel lies some share of
  the way from its cell's first color to the second. It becomes the second
  color where that share is above the threshold map's value at the pixel's
  position, and the first otherwise. Without a kernel, the default with
  `--bayer`, that's pure ordered dithering: regular patterns, no error
  passed on. With a kernel, it's the hybrid, which also passes on the
  difference between a pixel's value and its color.

The threshold comes from the pixel's position in the picture, not in its
cell, so a map of any size works. A map whose side divides the cell's
repeats in every cell: the 2×2, 4×4 and 8×8 Bayer maps on the Spectrum's
8×8 cells. The 16×16 map spreads its 257 tone steps over 2×2 cells.
How ordered dithering works in general: [ordered-dithering.md](../ordered-dithering.md).

## Which mode for which picture

It depends on the picture, so try both on yours, and look at the results
at 100% zoom.

| Picture | Best | Why |
|---|---|---|
| Drawn graphics, smooth shading, gradients; the classic look of much Spectrum art | Ordered: `--bayer 8` | Every tone is kept, as a pattern of the cell's two colors, shadows included. There are no streaks, since no error flows. `--bayer 4` gives a coarser pattern with fewer tone steps. |
| Photos with fine detail, especially on a light background | Error diffusion: `--kernel atkinson` | The dots go where the detail is, and Atkinson's extra contrast keeps edges crisp. A Bayer map lays the same pattern over everything, and on 8×8 cells it's as large as a cell, so small details turn into texture. |

On the Spectrum, an alternative worth trying for photos is two steps:
`--palette zx15 --kernel atkinson` first, then `--machine zx-spectrum
--kernel none` on the result. It gives a grain-like look, but keeps the
tones less faithfully.

Two things to know about error diffusion inside cells:

- **Atkinson loses dark and light tones.** It passes on only 3/4 of each
  error, so tones near black and near white get pushed to them. On the
  test images, the shadow side of a shaded sphere turns solid black.
- **Floyd–Steinberg can leave streaks,** thin lines of extreme pixels,
  mostly vertical. A cell can only mix along the line between its two
  colors, so error that points elsewhere, green error arriving in a
  red-and-black cell, say, can't be used up there. Floyd–Steinberg passes
  all of it on, so it builds up to the right and downwards, until a cell
  whose colors can express it turns it into a line of extreme pixels.
  Atkinson passes on only 3/4 of each error, so such error dies out.

This advice comes from the generated [test images](../test-images.md) and
from a portrait photo at 256×192.

## What it looks like

- **Attribute clash:** where colors change, the cell grid shows, and a
  colored edge steps from cell to cell. On the Spectrum this was called
  *attribute clash*, and it's much of what makes the pictures look
  authentic.
- **Inside a cell,** smooth shading becomes a pattern of the cell's two
  colors: regular with ordered dithering, irregular with error diffusion.
- **A cell that fits several candidates equally well** gets the one listed
  first. A machine lists the narrowest first, single colors and then pairs
  of near colors, which gives the calmest cells.

## Size

Any size works, for a poster in a machine's style, say. If the size isn't
a multiple of the cell size, the cells at the right and bottom edges are
smaller. A machine's own files need the exact size of its screen, 256×192
on the Spectrum. To bring a picture to that size, resize it with another
tool first, for example ImageMagick, where the `!` ignores the aspect
ratio:

```bash
magick photo.png -resize '256x192!' screen.png
```

## In the library

```purescript
import Puregrain.Cells (ditherCells, nearestInCell, orderedInCell)
import Puregrain.Kernel (atkinson, noDiffusion)
import Puregrain.Machine.ZxSpectrum as Zx
import Puregrain.Ordered (bayer)

-- ordered dithering inside the cells, with the 8 × 8 Bayer map
ordered = map (\m -> ditherCells noDiffusion (orderedInCell m) Zx.screen picture) (bayer 8)

-- error diffusion inside the cells, with Atkinson
diffused = ditherCells atkinson nearestInCell Zx.screen picture
```

`ditherCells` returns `{ cells, image }`: the candidate chosen for each
cell, row by row, and the dithered picture. `ditherBands` does the same
for a lazy stream of rows, one band at a time, so only one band is in
memory.

A machine's screen mode is a `CellMode`: the cell size, the candidates,
and each candidate's colors (`Zx.screen` for the Spectrum). For cells of
your own, write the record; the candidates can be the palettes themselves:

```purescript
import Data.Array.NonEmpty as NEA
import Puregrain.Cells (CellMode, CellPalette, colorPair)

-- 4 × 4 cells, each black and white, or blue and yellow
-- (black, white, blue and yellow are RGB values of your own)
mode :: CellMode CellPalette
mode =
  { size: { width: 4, height: 4 }
  , palette: identity
  , candidates: NEA.cons' (colorPair black white) [ colorPair blue yellow ]
  }
```

To change one part of a machine's mode, update its record, as in
`Zx.screen { candidates = fewer }`. The order of a pair's two colors
matters only for the ordered rule: the first is the base, and the second's
dots come in as a pixel nears it.

## Not supported (yet)

- **Other machines,** such as the Commodore 64's multicolor mode (4 colors
  per 4×8 cell, one of them shared by the whole screen), the MSX (8×1
  cells) and pseudo-graphics with characters. They're in
  [TODO.md](../../TODO.md).
- **Calmer error diffusion inside cells,** by clamping the error or by
  stopping it at cell borders: an idea in [TODO.md](../../TODO.md).
- **Dithering in linear light** instead of the stored sRGB values, as for
  every mode.
