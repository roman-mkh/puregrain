-- | The ZX Spectrum's screen: 8 × 8 cells, each with two colors, an ink
-- | and a paper, from the machine's 8 colors, plus one BRIGHT bit for both.
-- | With `Puregrain.Cells`, that gives images the Spectrum could show:
-- |
-- | ```purescript
-- | import Puregrain.Cells (ditherCells)
-- | import Puregrain.Machine.ZxSpectrum as Zx
-- |
-- | { cells, image } = ditherCells floydSteinberg Zx.cellSize Zx.attributePalette Zx.attributes picture
-- | ```
-- |
-- | `cells` holds each cell's `Attribute`: its ink, paper and BRIGHT, as a
-- | screen file needs them. The colors are those of
-- | `Puregrain.Palette.Presets.zxSpectrum`.
module Puregrain.Machine.ZxSpectrum
  ( Attribute
  , ink
  , paper
  , bright
  , attributes
  , attributePalette
  , cellSize
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Partial.Unsafe (unsafePartial)
import Puregrain.Cells (CellPalette, CellSize, colorPair, singleColor)
import Puregrain.Palette (distance2)
import Puregrain.Palette.Presets (zxSpectrum)
import Puregrain.Pixel (RGB)

-- | One cell's attribute: its ink and paper, as ZX color codes (0 black,
-- | 1 blue, 2 red, 3 magenta, 4 green, 5 cyan, 6 yellow, 7 white), and
-- | whether BRIGHT is set. Only the 71 values in `attributes` exist.
newtype Attribute = Attribute { ink :: Int, paper :: Int, bright :: Boolean }

derive instance Eq Attribute
derive newtype instance Show Attribute

-- | The ink's color code, 0 to 7.
ink :: Attribute -> Int
ink (Attribute a) = a.ink

-- | The paper's color code, 0 to 7.
paper :: Attribute -> Int
paper (Attribute a) = a.paper

-- | Whether BRIGHT is set, for both ink and paper.
bright :: Attribute -> Boolean
bright (Attribute a) = a.bright

-- | Every attribute that looks different: per brightness, 8 cells of a
-- | single color and 28 pairs, 72 in all, minus one, because all black
-- | looks the same with and without BRIGHT (it's listed once, without).
-- | Ink is the darker color, the lower code, and paper the lighter, as in
-- | the Spectrum's default of black ink on white paper; a single-color
-- | cell has ink = paper.
-- |
-- | They're listed in the order `Puregrain.Cells` tries them, where the
-- | earlier wins a tie: the single colors first, then the pairs by the
-- | distance between their two colors, nearest first (at equal distances,
-- | normal before bright, then by ink, then by paper). A cell that several
-- | palettes fit equally well thus gets the narrowest, the calmest.
attributes :: NonEmptyArray Attribute
attributes = NEA.appendArray normalSingles (brightSingles <> pairs)
  where
  attribute i p b = Attribute { ink: i, paper: p, bright: b }
  normalSingles = map (\c -> attribute c c false) (NEA.range 0 7)
  brightSingles = map (\c -> attribute c c true) (Array.range 1 7)
  pairs = Array.sortBy nearestFirst do
    b <- [ false, true ]
    i <- Array.range 0 6
    p <- Array.range (i + 1) 7
    pure (attribute i p b)
  nearestFirst x y =
    compare (spread x) (spread y) <> compare (bright x) (bright y) <> compare (ink x) (ink y)
      <> compare (paper x) (paper y)
  spread (Attribute a) = distance2 (color a.bright a.ink) (color a.bright a.paper)

-- | The attribute's colors, for `Puregrain.Cells`: the ink and paper, or
-- | the one color of a single-color cell.
attributePalette :: Attribute -> CellPalette
attributePalette (Attribute a) =
  if a.ink == a.paper then singleColor (color a.bright a.ink)
  else colorPair (color a.bright a.ink) (color a.bright a.paper)

-- | The Spectrum's cells: 8 × 8 pixels.
cellSize :: CellSize
cellSize = { width: 8, height: 8 }

-- | A color code's color at a brightness, from the `zxSpectrum` preset:
-- | its first 8 colors are codes 0 to 7 at normal brightness, the next 7
-- | codes 1 to 7 with BRIGHT set; bright black is black.
color :: Boolean -> Int -> RGB
color isBright code =
  unsafePartial (NEA.unsafeIndex zxSpectrum (if isBright && code > 0 then 7 + code else code))
