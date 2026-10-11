-- | Dithering with cells: the image is divided into cells of `width ×
-- | height` pixels, and each cell may use only one or two colors, chosen
-- | for that cell from a list of candidates. That's how the attribute
-- | cells of 8-bit home computers work, such as the ZX Spectrum's 8 × 8
-- | cells with an ink and a paper color.
-- |
-- | The image is processed in bands, one row of cells at a time. In each
-- | band, every cell gets the candidate whose colors fit the cell's
-- | original pixels best; then the band's rows are dithered, each pixel
-- | becoming the nearer of its cell's colors. The error diffusion runs
-- | across cell and band borders as usual. Two ways, with the same result:
-- |
-- | - `ditherCells`: an image in memory, all at once;
-- | - `ditherBands`: a lazy stream of rows, dithered band by band, each
-- |   band when it's needed, so only one band is in memory.
-- |
-- | ```purescript
-- | { cells, image } = ditherCells floydSteinberg size toPalette candidates original
-- | ```
-- |
-- | Candidates can be of any type: `toPalette` gives each one's colors as
-- | a `CellPalette`. A machine's own type can then keep what its colors
-- | mean, such as ink and paper; both functions return the candidates
-- | they chose.
module Puregrain.Cells
  ( CellSize
  , CellPalette
  , singleColor
  , colorPair
  , cellColors
  , ditherCells
  , ditherBands
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.CatQueue (CatQueue)
import Data.Either (Either(..))
import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
import Data.Maybe (Maybe(..), maybe)
import Data.Number (infinity)
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith, unsafePartial)
import Puregrain.Internal.Kernel (CompiledKernel, compileKernel)
import Puregrain.Internal.Row (orStop, stepRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Internal.Util (safeRange)
import Puregrain.Kernel (Kernel)
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

-- | Dithers an image in memory, an array of rows of `RGB` pixels, with
-- | cells. Returns the candidate chosen for each cell, as an array of cell
-- | rows, top to bottom, each an array of cells, left to right, and the
-- | dithered image. An image whose size isn't a multiple of the cell size
-- | gets partial cells at the right and bottom edges.
-- |
-- | A candidate's score for a cell is the sum, over the cell's original
-- | pixels, of each pixel's squared distance (in r, g and b) to the
-- | nearest color the candidate's palette can produce by dithering. For
-- | two colors, that's the nearest point on the straight segment between
-- | them, since any mix of the two can be dithered; for one color, it's
-- | that color. A middle gray, for example, fits black and white
-- | perfectly, but blue and white poorly. The distance is measured in the
-- | stored values, where the error diffusion mixes too.
-- |
-- | The lowest score wins. Candidates are tried in the order given, and
-- | on a tie the earlier one wins, so the order decides between palettes
-- | that fit equally well (it may put the narrowest first, for the
-- | calmest cells).
-- |
-- | All rows must have the same length. A row of a different length is a
-- | bug in the caller: `ditherCells` stops with an error naming it.
ditherCells
  :: forall c
   . Kernel
  -> CellSize
  -> (c -> CellPalette)
  -> NonEmptyArray c
  -> Array (Array RGB)
  -> { cells :: Array (Array c), image :: Array (Array RGB) }
ditherCells kernel size toPalette candidates image =
  { cells: map _.cells bands, image: Array.concatMap _.rows bands }
  where
  setup = bandSetup kernel size toPalette candidates
  ch = setup.cellHeight
  bandsIn = map (\i -> Array.slice (i * ch) (i * ch + ch) image) (safeRange 0 ((Array.length image + ch - 1) / ch - 1))
  next state rows =
    let
      Tuple state' band = orStop (stepBand setup state rows)
    in
      { accum: state', value: band }
  bands = (mapAccumL next (initState setup.compiled :: DitherState CatQueue RGB) bandsIn).value

-- | Dithers a stream of rows with cells: a lazy list of `RGB` rows in, a
-- | lazy list of bands out, one per row of cells, top to bottom. Each band
-- | holds the candidates chosen for its cells, left to right, and its
-- | dithered rows. A band's rows are read and dithered only when the band
-- | is first needed, so only one band is in memory, and the input may even
-- | be endless. Cells are chosen and dithered exactly as by `ditherCells`,
-- | with the same result.
-- |
-- | All rows must have the same length. A row of a different length is a
-- | bug in the caller: when its band is reached, `ditherBands` stops with
-- | an error naming the row (the bands before it have come out already).
ditherBands
  :: forall c
   . Kernel
  -> CellSize
  -> (c -> CellPalette)
  -> NonEmptyArray c
  -> LL.List (Array RGB)
  -> LL.List { cells :: Array c, rows :: Array (Array RGB) }
ditherBands kernel size toPalette candidates input = go (initState setup.compiled) input
  where
  setup = bandSetup kernel size toPalette candidates

  -- All the work happens inside `defer`: a band's rows are read and
  -- dithered only when its cell is forced.
  go :: DitherState CatQueue RGB -> LL.List (Array RGB) -> LL.List { cells :: Array c, rows :: Array (Array RGB) }
  go state rows = List $ defer \_ ->
    let
      Tuple bandIn rest = takeBand setup.cellHeight rows
    in
      if Array.null bandIn then Nil
      else
        let
          Tuple state' band = orStop (stepBand setup state bandIn)
        in
          Cons band (go state' rest)

-- | What every band needs, prepared once per image: the compiled kernel,
-- | the cell size (at least 1 × 1), and each candidate with its palette.
type Setup c =
  { compiled :: CompiledKernel
  , cellWidth :: Int
  , cellHeight :: Int
  , candidates :: NonEmptyArray (Tuple c CellPalette)
  }

bandSetup :: forall c. Kernel -> CellSize -> (c -> CellPalette) -> NonEmptyArray c -> Setup c
bandSetup kernel size toPalette candidates =
  { compiled: compileKernel kernel
  , cellWidth: max 1 size.width
  , cellHeight: max 1 size.height
  , candidates: map (\c -> Tuple c (toPalette c)) candidates
  }

-- | One band: chooses its row of cells from the original pixels, then
-- | dithers its rows with them, carrying the diffusion state on. `Left`
-- | for a row of a different length (`stepRow`'s check).
stepBand
  :: forall c
   . Setup c
  -> DitherState CatQueue RGB
  -> Array (Array RGB)
  -> Either String (Tuple (DitherState CatQueue RGB) { cells :: Array c, rows :: Array (Array RGB) })
stepBand setup state0 rows = go state0 0 []
  where
  chosen = bandCells setup rows
  quantizer = bandQuantize setup.cellWidth (map snd chosen)
  go state i out = case Array.index rows i of
    Nothing -> Right (Tuple state { cells: map fst chosen, rows: out })
    Just row -> case stepRow setup.compiled quantizer state row of
      Left problem -> Left problem
      Right (Tuple state' dithered) -> go state' (i + 1) (Array.snoc out dithered)

-- | The candidate, with its palette, chosen for each cell of a band, left
-- | to right.
bandCells :: forall c. Setup c -> Array (Array RGB) -> Array (Tuple c CellPalette)
bandCells setup rows = map (\cx -> bestCandidate setup.candidates (cellPixels cx)) (safeRange 0 (columns - 1))
  where
  cw = setup.cellWidth
  columns = (maybe 0 Array.length (Array.head rows) + cw - 1) / cw
  -- The cell's pixels, row by row; fewer at the right edge.
  cellPixels cx = Array.concatMap (Array.slice (cx * cw) (cx * cw + cw)) rows

-- | The quantizer for a band's rows: each pixel becomes the nearer of its
-- | cell's colors (the first one on a tie).
bandQuantize :: Int -> Array CellPalette -> Quantize RGB
bandQuantize cellWidth palettes = quantizeWith \{ x } v -> case Array.index palettes (x / cellWidth) of
  Just palette -> nearest palette v
  -- `stepRow` rejects a row of a different length before quantizing it,
  -- and the band's cells span the width of its rows.
  Nothing -> unsafeCrashWith "Puregrain.Cells.bandQuantize: pixel outside its band's cells - row width invariant violated"

-- | The first `n` rows (fewer at the end of the input) and the rest,
-- | reading no more than those `n` rows.
takeBand :: forall a. Int -> LL.List a -> Tuple (Array a) (LL.List a)
takeBand n = go [] n
  where
  go acc k rows =
    if k <= 0 then Tuple acc rows
    else case LL.step rows of
      Nil -> Tuple acc LL.nil
      Cons row rest -> go (Array.snoc acc row) (k - 1) rest

-- | The candidate with the lowest score; the earlier one on a tie. Two
-- | shortcuts leave the result unchanged: a score of 0 can't be beaten, so
-- | the search stops there, and a candidate's sum stops as soon as it
-- | reaches the best score so far, since it can no longer win.
bestCandidate :: forall c. NonEmptyArray (Tuple c CellPalette) -> Array RGB -> Tuple c CellPalette
bestCandidate candidates pixels = go 1 first (score infinity (snd first) pixels)
  where
  first = NEA.head candidates
  others = NEA.toArray candidates
  count = Array.length others
  go i best bestScore =
    if bestScore == 0.0 || i >= count then best
    else
      let
        candidate = unsafePartial (Array.unsafeIndex others i)
        s = score bestScore (snd candidate) pixels
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

-- | The nearer of the palette's colors; the first one on a tie.
nearest :: CellPalette -> RGB -> RGB
nearest (CellPalette s) v =
  if s.length2 == 0.0 || distance2 v s.first <= distance2 v s.second then s.first else s.second
