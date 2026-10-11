-- | Dithering with cells: the image is divided into cells of `width ×
-- | height` pixels, and each cell may use only one or two colors, chosen
-- | for that cell from a list of candidates. That's how the attribute
-- | cells of 8-bit home computers work, such as the ZX Spectrum's 8 × 8
-- | cells with an ink and a paper color.
-- |
-- | It takes two passes. `chooseCells` picks, for each cell, the candidate
-- | whose colors fit the cell's pixels best. `cellQuantize` then gives the
-- | dithering a quantizer that picks, for each pixel, the nearer of its
-- | cell's colors. The error diffusion works across cell borders as usual.
-- |
-- | ```purescript
-- | cells = chooseCells size toPalette candidates image
-- | dithered = ditherImage floydSteinberg (cellQuantize size toPalette cells) image
-- | ```
-- |
-- | Candidates can be of any type: `toPalette` gives each one's colors as
-- | a `CellPalette`. A machine's own type can then keep what its colors
-- | mean, such as ink and paper.
module Puregrain.Cells
  ( CellSize
  , CellPalette
  , singleColor
  , colorPair
  , cellColors
  , chooseCells
  , cellQuantize
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Maybe (Maybe(..), maybe)
import Data.Number (infinity)
import Data.Tuple (Tuple(..))
import Partial.Unsafe (unsafeCrashWith, unsafePartial)
import Puregrain.Internal.Util (safeRange)
import Puregrain.Palette (distance2)
import Puregrain.Pixel (RGB(..))
import Puregrain.Quantize (Quantize, quantizeWith)

-- | The size of a cell in pixels. A width or height below 1 counts as 1.
type CellSize = { width :: Int, height :: Int }

-- | The colors one cell may use: one color, or two that dithering mixes.
-- | Build it with `singleColor` or `colorPair`. The two colors are treated
-- | alike: their order doesn't change which cells choose them, nor the
-- | dithered result.
newtype CellPalette = CellPalette
  { first :: RGB
  , second :: RGB
  -- Precomputed for the score: second − first, and its squared length
  -- (0 for a single color).
  , direction :: { r :: Number, g :: Number, b :: Number }
  , length2 :: Number
  }

-- | A cell palette of one color.
singleColor :: RGB -> CellPalette
singleColor c = CellPalette { first: c, second: c, direction: { r: 0.0, g: 0.0, b: 0.0 }, length2: 0.0 }

-- | A cell palette of two colors. The same color twice is a single color.
colorPair :: RGB -> RGB -> CellPalette
colorPair a@(RGB p) b@(RGB q) =
  if a == b then singleColor a
  else
    let
      d = { r: q.r - p.r, g: q.g - p.g, b: q.b - p.b }
    in
      CellPalette { first: a, second: b, direction: d, length2: d.r * d.r + d.g * d.g + d.b * d.b }

-- | The palette's colors: one, or two in the order they were given.
cellColors :: CellPalette -> NonEmptyArray RGB
cellColors (CellPalette s) =
  if s.length2 == 0.0 then NEA.singleton s.first else NEA.cons' s.first [ s.second ]

-- | For each cell of the image, the candidate whose colors fit the cell's
-- | pixels best: an array of cell rows, top to bottom, each an array of
-- | cells, left to right. An image whose size isn't a multiple of the
-- | cell size gets partial cells at the right and bottom edges.
-- |
-- | A candidate's score for a cell is the sum, over the cell's pixels, of
-- | each pixel's squared distance (in r, g and b) to the nearest color the
-- | candidate's palette can produce by dithering. For two colors, that's
-- | the nearest point on the straight segment between them, since any mix
-- | of the two can be dithered; for one color, it's that color. A middle
-- | gray, for example, fits black and white perfectly, but blue and white
-- | poorly. The distance is measured in the stored values, where the error
-- | diffusion mixes too.
-- |
-- | The lowest score wins. Candidates are tried in the order given, and
-- | on a tie the earlier one wins, so the order decides between palettes
-- | that fit equally well (it may put the narrowest first, for the
-- | calmest cells).
chooseCells
  :: forall c
   . CellSize
  -> (c -> CellPalette)
  -> NonEmptyArray c
  -> Array (Array RGB)
  -> Array (Array c)
chooseCells size toPalette candidates image =
  map (\cy -> map (\cx -> bestCandidate withPalettes (cellPixels cx cy)) (safeRange 0 (columns - 1)))
    (safeRange 0 (rows - 1))
  where
  cw = max 1 size.width
  ch = max 1 size.height
  columns = (maybe 0 Array.length (Array.head image) + cw - 1) / cw
  rows = (Array.length image + ch - 1) / ch
  -- Each candidate's palette, built once rather than for every cell.
  withPalettes = map (\c -> Tuple c (toPalette c)) candidates
  -- The cell's pixels, row by row; fewer at the edges.
  cellPixels cx cy =
    Array.concatMap (Array.slice (cx * cw) (cx * cw + cw)) (Array.slice (cy * ch) (cy * ch + ch) image)

-- | The candidate with the lowest score; the earlier one on a tie. Two
-- | shortcuts leave the result unchanged: a score of 0 can't be beaten, so
-- | the search stops there, and a candidate's sum stops as soon as it
-- | reaches the best score so far, since it can no longer win.
bestCandidate :: forall c. NonEmptyArray (Tuple c CellPalette) -> Array RGB -> c
bestCandidate candidates pixels = go 1 firstCandidate (score infinity firstPalette pixels)
  where
  Tuple firstCandidate firstPalette = NEA.head candidates
  others = NEA.toArray candidates
  count = Array.length others
  go i best bestScore =
    if bestScore == 0.0 || i >= count then best
    else
      let
        Tuple candidate palette = unsafePartial (Array.unsafeIndex others i)
        s = score bestScore palette pixels
      in
        if s < bestScore then go (i + 1) candidate s else go (i + 1) best bestScore

-- | The sum of the pixels' errors, stopping once it reaches `limit`.
score :: Number -> CellPalette -> Array RGB -> Number
score limit palette pixels = go 0 0.0
  where
  count = Array.length pixels
  go i sum =
    if sum >= limit || i >= count then sum
    else go (i + 1) (sum + segmentError palette (unsafePartial (Array.unsafeIndex pixels i)))

-- | The squared distance from a pixel to the nearest color the palette
-- | can produce: the nearest point on the segment from `first` to
-- | `second` (for a single color, `first` itself).
segmentError :: CellPalette -> RGB -> Number
segmentError (CellPalette s) (RGB p) = case s.first of
  RGB a ->
    let
      vr = p.r - a.r
      vg = p.g - a.g
      vb = p.b - a.b
      -- How far along the segment the nearest point lies, from 0 (first)
      -- to 1 (second).
      t =
        if s.length2 == 0.0 then 0.0
        else clamp 0.0 1.0 ((vr * s.direction.r + vg * s.direction.g + vb * s.direction.b) / s.length2)
      er = vr - t * s.direction.r
      eg = vg - t * s.direction.g
      eb = vb - t * s.direction.b
    in
      er * er + eg * eg + eb * eb

-- | The quantizer for the dithering pass: each pixel becomes the nearer of
-- | its cell's colors (the first one on a tie). Give it the cells that
-- | `chooseCells` chose for the same image, with the same cell size and
-- | `toPalette`.
-- |
-- | A pixel outside those cells, because the cells were chosen for a
-- | smaller image, is a bug in the caller: the dithering stops with an
-- | error naming the pixel.
cellQuantize :: forall c. CellSize -> (c -> CellPalette) -> Array (Array c) -> Quantize RGB
cellQuantize size toPalette cells = quantizeWith \{ x, y } v -> nearest (paletteAt x y) v
  where
  cw = max 1 size.width
  ch = max 1 size.height
  -- Each cell's palette, built once rather than for every pixel.
  palettes = map (map toPalette) cells
  paletteAt x y = case Array.index palettes (y / ch) >>= \row -> Array.index row (x / cw) of
    Just palette -> palette
    Nothing ->
      unsafeCrashWith
        ( "puregrain: pixel (" <> show x <> ", " <> show y <> ") is outside the cells cellQuantize was given ("
            <> show (Array.length palettes) <> " rows of cells of " <> show cw <> " × " <> show ch
            <> " pixels); choose the cells from the same image"
        )

-- | The nearer of the palette's colors; the first one on a tie.
nearest :: CellPalette -> RGB -> RGB
nearest (CellPalette s) v =
  if s.length2 == 0.0 || distance2 v s.first <= distance2 v s.second then s.first else s.second
