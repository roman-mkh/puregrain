-- | The Commodore 64's hires bitmap screen: 320 × 200 pixels in cells of
-- | 8 × 8, each cell with two of the machine's 16 colors, a foreground and
-- | a background, chosen freely. With `Puregrain.Cells`, that gives
-- | pictures the C64 could show:
-- |
-- | ```purescript
-- | import Puregrain.Cells (ditherCells, nearestInCell, orderedInCell)
-- | import Puregrain.Machine.C64 as C64
-- |
-- | -- ordered dithering inside the cells, with a threshold map m
-- | { cells, image } = ditherCells noDiffusion (orderedInCell m) C64.hiresScreen picture
-- |
-- | -- error diffusion inside the cells
-- | { cells, image } = ditherCells atkinson nearestInCell C64.hiresScreen picture
-- | ```
-- |
-- | `cells` holds each cell's `HiresCell`: its foreground and background,
-- | as the machine's screen memory needs them. The colors are those of
-- | `Puregrain.Palette.Presets.c64`. The C64's multicolor mode isn't
-- | supported yet.
module Puregrain.Machine.C64
  ( HiresCell
  , foreground
  , background
  , hiresCells
  , hiresPalette
  , hiresScreen
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Partial.Unsafe (unsafePartial)
import Puregrain.Cells (CellMode, CellPalette, colorPair, singleColor)
import Puregrain.Palette (distance2)
import Puregrain.Palette.Presets (c64)
import Puregrain.Pixel (RGB(..))

-- | One hires cell's colors: the foreground, the color of the cell's 1
-- | bits, and the background, the color of its 0 bits, as C64 color codes
-- | (0 black, 1 white, 2 red, 3 cyan, 4 purple, 5 green, 6 blue, 7 yellow,
-- | 8 orange, 9 brown, 10 light red, 11 dark grey, 12 grey, 13 light
-- | green, 14 light blue, 15 light grey). Only the 136 values in
-- | `hiresCells` exist.
newtype HiresCell = HiresCell { foreground :: Int, background :: Int }

derive instance Eq HiresCell
derive newtype instance Show HiresCell

-- | The foreground's color code, 0 to 15: the color of the cell's 1 bits.
foreground :: HiresCell -> Int
foreground (HiresCell c) = c.foreground

-- | The background's color code, 0 to 15: the color of the cell's 0 bits.
background :: HiresCell -> Int
background (HiresCell c) = c.background

-- | Every hires cell that looks different: the 16 single colors and the
-- | 120 pairs, 136 in all. In a pair, the foreground is the darker color
-- | and the background the lighter, as with the ZX Spectrum's black ink on
-- | white paper. Darker means a lower luma, 0.299 R + 0.587 G + 0.114 B,
-- | since the C64's color codes aren't in order of brightness. A
-- | single-color cell has foreground = background.
-- |
-- | They're listed in the order `Puregrain.Cells` tries them, where the
-- | earlier wins a tie: the single colors first, by code, then the pairs by
-- | the distance between their two colors, nearest first (at equal
-- | distances, by foreground, then by background). A cell that several
-- | palettes fit equally well thus gets the narrowest, the calmest.
hiresCells :: NonEmptyArray HiresCell
hiresCells = NEA.appendArray singles pairs
  where
  singles = map (\c -> HiresCell { foreground: c, background: c }) (NEA.range 0 15)
  pairs = Array.sortBy nearestFirst do
    a <- Array.range 0 14
    b <- Array.range (a + 1) 15
    -- On exactly equal luma, the lower code is the foreground.
    pure
      if luma (color a) <= luma (color b) then HiresCell { foreground: a, background: b }
      else HiresCell { foreground: b, background: a }
  nearestFirst x y =
    compare (spread x) (spread y) <> compare (foreground x) (foreground y)
      <> compare (background x) (background y)
  spread c = distance2 (color (foreground c)) (color (background c))

-- | The cell's colors, for `Puregrain.Cells`: the foreground, then the
-- | background, or the one color of a single-color cell. With
-- | `orderedInCell`, the order means that a cell is foreground, with
-- | background dots added as a pixel nears the background.
hiresPalette :: HiresCell -> CellPalette
hiresPalette (HiresCell c) =
  if c.foreground == c.background then singleColor (color c.foreground)
  else colorPair (color c.foreground) (color c.background)

-- | The C64's hires screen mode, for `Puregrain.Cells`: cells of 8 × 8
-- | pixels, each using one of the `hiresCells`, tried in their order, with
-- | `hiresPalette`'s colors.
hiresScreen :: CellMode HiresCell
hiresScreen = { size: { width: 8, height: 8 }, palette: hiresPalette, candidates: hiresCells }

-- | A color code's color, from the `c64` preset, which lists the colors in
-- | code order.
color :: Int -> RGB
color code = unsafePartial (NEA.unsafeIndex c64 code)

-- | A color's brightness as luma: 0.299 R + 0.587 G + 0.114 B.
luma :: RGB -> Number
luma (RGB p) = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
