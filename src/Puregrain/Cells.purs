-- | Dithering with cells: the image is divided into cells of `width ×
-- | height` pixels, and each cell may use only one or two colors, chosen
-- | for it from a list of candidates. That's how the attribute cells of
-- | 8-bit home computers work, such as the ZX Spectrum's 8 × 8 cells with
-- | an ink and a paper color (`Puregrain.Machine.ZxSpectrum`). A
-- | `CellMode` holds the cell size and the candidates; a machine module
-- | exports one per screen mode. How it works and which rule suits which
-- | picture: [docs/machine-screens/](https://github.com/roman-mkh/puregrain/blob/master/docs/machine-screens/README.md).
-- |
-- | The image is processed in bands, one row of cells at a time. In each
-- | band:
-- |
-- | 1. Every cell gets the candidate that fits its original pixels best.
-- |    A candidate's score is the sum, over the cell's pixels, of each
-- |    pixel's squared distance (in r, g and b) to the nearest color the
-- |    candidate can produce: the nearest point on the segment between its
-- |    two colors, since dithering can mix any share of them, or its one
-- |    color. The lowest score wins; on a tie, the earlier candidate. A
-- |    middle gray, for example, fits black and white perfectly, blue and
-- |    white poorly.
-- | 2. The band's rows are dithered: a `CellQuantizer` turns each pixel
-- |    into one of its cell's colors, and the kernel passes the error on,
-- |    across cell and band borders.
-- |
-- | `ditherCells` works on an image in memory, `ditherBands` on a lazy
-- | stream of rows, with the same result:
-- |
-- | ```purescript
-- | -- error diffusion inside the cells
-- | ditherCells floydSteinberg nearestInCell mode image
-- |
-- | -- pure ordered dithering inside the cells, with a threshold map m
-- | ditherCells noDiffusion (orderedInCell m) mode image
-- | ```
-- |
-- | `ditherCellsBy` and `ditherBandsBy` take their settings as a
-- | `Puregrain.Dither.DitherParams` (the kernel, the gamma, …) in place of
-- | the kernel; `ditherCellsWith` and `ditherBandsWith` take a `Gamma` from
-- | `Puregrain.Gamma` and a kernel. Under a gamma the cells are the same,
-- | with the rows dithered in light.
module Puregrain.Cells
  ( CellSize
  , CellPalette
  , singleColor
  , colorPair
  , cellColors
  , CellMode
  , CellQuantizer
  , nearestInCell
  , orderedInCell
  , ditherCellsBy
  , ditherCells
  , ditherCellsWith
  , ditherBandsBy
  , ditherBands
  , ditherBandsWith
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
import Puregrain.Internal.Gamma (Conversion, Gamma, conversionFor, isOff)
import Puregrain.Internal.Image (rowsIn, rowsOut)
import Puregrain.Internal.Params (CompiledParams, DitherParams, compileParams, defaults, gammaOf, withGamma, withKernel)
import Puregrain.Internal.Row (orStop, stepRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Internal.Util (safeRange)
import Puregrain.Kernel (Kernel)
import Puregrain.Ordered (ThresholdMap, thresholdAt)
import Puregrain.Palette (distance2)
import Puregrain.Pixel (RGB(..))
import Puregrain.Internal.Quantize (Quantizer)

-- | The size of a cell in pixels, for `CellMode`. A width or height below
-- | 1 counts as 1.
type CellSize = { width :: Int, height :: Int }

-- | The colors one cell may use: one color, or two that dithering mixes.
-- | Build it with `singleColor` or `colorPair`. The order of two colors
-- | doesn't change which cells choose them, nor what `nearestInCell`
-- | gives; with `orderedInCell` it sets the pattern's direction.
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
-- |
-- | - `RGB`: the first color.
-- | - `RGB`: the second color; the order matters only for
-- |   `orderedInCell`.
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

-- | A screen mode for cells: how big a cell is, and which palettes a cell
-- | may use. A machine module exports one per screen mode, such as
-- | `Puregrain.Machine.ZxSpectrum.screen`.
-- |
-- | - `c`: the candidate type, anything that stands for a cell's palette
-- |   (for the ZX Spectrum, `Attribute`).
-- | - `size`: the cell's width and height in pixels.
-- | - `palette`: a candidate's colors.
-- | - `candidates`: what a cell may use, in the order they're tried; on a
-- |   tie the earlier wins.
-- |
-- | For cells of your own, write the record; the candidates can be the
-- | palettes themselves:
-- |
-- | ```purescript
-- | mode :: CellMode CellPalette
-- | mode =
-- |   { size: { width: 4, height: 4 }
-- |   , palette: identity
-- |   , candidates: NEA.cons' (colorPair black white) [ colorPair blue yellow ]
-- |   }
-- | ```
-- |
-- | To change one part of a machine's mode, update its record, as in
-- | `Zx.screen { candidates = fewer }`.
type CellMode c =
  { size :: CellSize
  , palette :: c -> CellPalette
  , candidates :: NonEmptyArray c
  }

-- | How a pixel becomes one of its cell's colors. Build it with
-- | `nearestInCell` or `orderedInCell`.
data CellQuantizer = NearestRule | OrderedRule ThresholdMap

-- | Each pixel becomes the nearer of its cell's colors, by squared RGB
-- | distance (the first on a tie). With a kernel, that's error diffusion
-- | inside the cells.
nearestInCell :: CellQuantizer
nearestInCell = NearestRule

-- | Ordered dithering inside the cells. A pixel lies some fraction of the
-- | way from its cell's first color to the second, measured along the
-- | line between them; it becomes the second color where that fraction is
-- | above the map's threshold at the pixel's position, else the first. A
-- | single-color cell keeps its color.
-- |
-- | - `ThresholdMap`: the thresholds, from `Puregrain.Ordered.bayer` or
-- |   `compileThresholdMap`. Positions count from the image's corner, so
-- |   any size works: a map whose side divides the cell's repeats in every
-- |   cell, a larger one spreads more tone steps over several cells.
-- |
-- | With `noDiffusion`, that's pure ordered dithering. With another kernel
-- | it's the hybrid: the difference between a pixel's value and its color
-- | is passed on.
orderedInCell :: ThresholdMap -> CellQuantizer
orderedInCell = OrderedRule

-- | Dithers an image in memory with cells, with the settings given.
-- |
-- | - `c`: the mode's candidate type (see `CellMode`).
-- | - `DitherParams`: the kernel, the gamma and the scan, from
-- |   `Puregrain.Dither.defaults` and the `with…` functions.
-- | - `CellQuantizer`: how each pixel picks one of its cell's colors.
-- | - `CellMode c`: the cell size, and the candidates with their colors.
-- | - `Array (Array RGB)`: the image, rows top to bottom, all of the same
-- |   length.
-- |
-- | Returns the candidate chosen for each cell, as rows of cells (top to
-- | bottom, each left to right), and the dithered image. An image whose
-- | size isn't a multiple of the cell size gets partial cells at the
-- | right and bottom edges. Stops with an error naming a row whose length
-- | differs from the first row's.
-- |
-- | Under a gamma other than `gammaOff`, each cell's colors are still
-- | chosen from the original pixels, as stored, so the cells are the same;
-- | the band's rows are then dithered in light. `orderedInCell` measures
-- | where a pixel lies between its cell's two colors in light;
-- | `nearestInCell` still picks the nearer color on stored values, while
-- | the error stays in light. When the cells' colors are whole numbers from
-- | 0 to 255, as a machine's are, every pixel comes out as exactly one of
-- | its cell's colors, as a screen file needs.
-- |
-- | ```purescript
-- | ditherCellsBy (defaults # withKernel atkinson) nearestInCell Zx.screen picture
-- | ```
ditherCellsBy
  :: forall c
   . DitherParams
  -> CellQuantizer
  -> CellMode c
  -> Array (Array RGB)
  -> { cells :: Array (Array c), image :: Array (Array RGB) }
ditherCellsBy params = ditherCellsVia (conversionFor (gammaOf params)) (compileParams params)

-- | Dithers an image in memory with cells, with a kernel and no other
-- | setting.
-- |
-- | - `c`, `CellQuantizer`, `CellMode c`, `Array (Array RGB)`: as for
-- |   `ditherCellsBy`.
-- | - `Kernel`: where each pixel's error goes; `noDiffusion` for nowhere.
-- |
-- | Returns what `ditherCellsBy (defaults # withKernel kernel)` returns.
ditherCells
  :: forall c
   . Kernel
  -> CellQuantizer
  -> CellMode c
  -> Array (Array RGB)
  -> { cells :: Array (Array c), image :: Array (Array RGB) }
ditherCells kernel = ditherCellsBy (defaults # withKernel kernel)

-- | Dithers an image in memory with cells, with a gamma and a kernel.
-- |
-- | - `c`: as for `ditherCellsBy`.
-- | - `Gamma`: how the stored numbers turn into light: `gammaOff`, the same
-- |   as `ditherCells`, or a curve from `Puregrain.Gamma`.
-- | - `Kernel`, `CellQuantizer`, `CellMode c`, `Array (Array RGB)`: as for
-- |   `ditherCells`.
-- |
-- | Returns what `ditherCellsBy (defaults # withKernel kernel # withGamma
-- | gamma)` returns.
ditherCellsWith
  :: forall c
   . Gamma
  -> Kernel
  -> CellQuantizer
  -> CellMode c
  -> Array (Array RGB)
  -> { cells :: Array (Array c), image :: Array (Array RGB) }
ditherCellsWith gamma kernel = ditherCellsBy (defaults # withKernel kernel # withGamma gamma)

ditherCellsVia
  :: forall c
   . Conversion RGB
  -> CompiledParams
  -> CellQuantizer
  -> CellMode c
  -> Array (Array RGB)
  -> { cells :: Array (Array c), image :: Array (Array RGB) }
ditherCellsVia conversion compiled rule mode image =
  { cells: map _.cells bands, image: Array.concatMap _.rows bands }
  where
  setup = bandSetup conversion compiled rule mode
  ch = setup.cellHeight
  bandsIn = map (\i -> Array.slice (i * ch) (i * ch + ch) image) (safeRange 0 ((Array.length image + ch - 1) / ch - 1))
  next state rows =
    let
      Tuple state' band = orStop (stepBand setup state rows)
    in
      { accum: state', value: band }
  bands = (mapAccumL next (initState setup.compiled.kernel :: DitherState CatQueue RGB) bandsIn).value

-- | Dithers a stream of rows with cells, one band (row of cells) at a
-- | time, with the settings given.
-- |
-- | - `c`, `DitherParams`, `CellQuantizer` and `CellMode c`: as for
-- |   `ditherCellsBy`.
-- | - `LL.List (Array RGB)`: the image as a lazy list of rows, top to
-- |   bottom, all of the same length; it may be endless.
-- |
-- | Returns a lazy list of bands, top to bottom, each with the candidates
-- | chosen for its cells (left to right) and its dithered rows: the same
-- | result as `ditherCellsBy`. A band's rows are read and dithered only when
-- | the band is first needed, so only one band is in memory. When a band
-- | holds a row whose length differs from the first row's, `ditherBands`
-- | stops there with an error naming it; the bands before it have come out.
ditherBandsBy
  :: forall c
   . DitherParams
  -> CellQuantizer
  -> CellMode c
  -> LL.List (Array RGB)
  -> LL.List { cells :: Array c, rows :: Array (Array RGB) }
ditherBandsBy params = ditherBandsVia (conversionFor (gammaOf params)) (compileParams params)

-- | Dithers a stream of rows with cells, one band at a time, with a kernel
-- | and no other setting.
-- |
-- | - `c`, `CellQuantizer`, `CellMode c`, `LL.List (Array RGB)`: as for
-- |   `ditherBandsBy`.
-- | - `Kernel`: where each pixel's error goes; `noDiffusion` for nowhere.
-- |
-- | Returns what `ditherBandsBy (defaults # withKernel kernel)` returns.
ditherBands
  :: forall c
   . Kernel
  -> CellQuantizer
  -> CellMode c
  -> LL.List (Array RGB)
  -> LL.List { cells :: Array c, rows :: Array (Array RGB) }
ditherBands kernel = ditherBandsBy (defaults # withKernel kernel)

-- | Dithers a stream of rows with cells, one band at a time, with a gamma
-- | and a kernel.
-- |
-- | - `c` and `Gamma`: as for `ditherCellsWith`.
-- | - `Kernel`, `CellQuantizer`, `CellMode c`, `LL.List (Array RGB)`: as for
-- |   `ditherBands`.
-- |
-- | Returns what `ditherBandsBy (defaults # withKernel kernel # withGamma
-- | gamma)` returns.
ditherBandsWith
  :: forall c
   . Gamma
  -> Kernel
  -> CellQuantizer
  -> CellMode c
  -> LL.List (Array RGB)
  -> LL.List { cells :: Array c, rows :: Array (Array RGB) }
ditherBandsWith gamma kernel = ditherBandsBy (defaults # withKernel kernel # withGamma gamma)

ditherBandsVia
  :: forall c
   . Conversion RGB
  -> CompiledParams
  -> CellQuantizer
  -> CellMode c
  -> LL.List (Array RGB)
  -> LL.List { cells :: Array c, rows :: Array (Array RGB) }
ditherBandsVia conversion compiled rule mode input = go (initState setup.compiled.kernel) input
  where
  setup = bandSetup conversion compiled rule mode

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

-- | What every band needs, prepared once per image: the conversion to
-- | light, the compiled settings, the rule inside the cells, the cell size (at
-- | least 1 × 1), and each candidate with its palette.
type Setup c =
  { conversion :: Conversion RGB
  , compiled :: CompiledParams
  , rule :: CellQuantizer
  , cellWidth :: Int
  , cellHeight :: Int
  , candidates :: NonEmptyArray (Tuple c CellPalette)
  }

bandSetup :: forall c. Conversion RGB -> CompiledParams -> CellQuantizer -> CellMode c -> Setup c
bandSetup conversion compiled rule mode =
  { conversion
  , compiled
  , rule
  , cellWidth: max 1 mode.size.width
  , cellHeight: max 1 mode.size.height
  , candidates: map (\c -> Tuple c (mode.palette c)) mode.candidates
  }

-- | One band: chooses its row of cells from the original pixels, as
-- | stored, then dithers its rows with them, in light when there's a
-- | curve, carrying the diffusion state on. `Left` for a row of a
-- | different length (`stepRow`'s check).
stepBand
  :: forall c
   . Setup c
  -> DitherState CatQueue RGB
  -> Array (Array RGB)
  -> Either String (Tuple (DitherState CatQueue RGB) { cells :: Array c, rows :: Array (Array RGB) })
stepBand setup state0 rows = go state0 0 []
  where
  chosen = bandCells setup rows
  quantizer = bandQuantize setup.conversion setup.rule setup.cellWidth (map snd chosen)
  toLight = rowsIn setup.conversion
  fromLight = rowsOut setup.conversion
  go state i out = case Array.index rows i of
    Nothing -> Right (Tuple state { cells: map fst chosen, rows: out })
    Just row -> case stepRow setup.compiled quantizer state (toLight row) of
      Left problem -> Left problem
      Right (Tuple state' dithered) -> go state' (i + 1) (Array.snoc out (fromLight dithered))

-- | The candidate, with its palette, chosen for each cell of a band, left
-- | to right.
bandCells :: forall c. Setup c -> Array (Array RGB) -> Array (Tuple c CellPalette)
bandCells setup rows = map (\cx -> bestCandidate setup.candidates (cellPixels cx)) (safeRange 0 (columns - 1))
  where
  cw = setup.cellWidth
  columns = (maybe 0 Array.length (Array.head rows) + cw - 1) / cw
  -- The cell's pixels, row by row; fewer at the right edge.
  cellPixels cx = Array.concatMap (Array.slice (cx * cw) (cx * cw + cw)) rows

-- | The quantizer for a band's rows, resolved: each pixel becomes one of
-- | its cell's colors, by the rule. With a curve, the pixels arrive in
-- | light: `nearestInCell` compares on stored values, bringing each pixel
-- | back (table first) and taking the chosen color to light; `orderedInCell`
-- | measures between the cell's colors taken to light, once per band.
bandQuantize :: Conversion RGB -> CellQuantizer -> Int -> Array CellPalette -> Quantizer RGB
bandQuantize conversion rule cellWidth palettes =
  if isOff conversion.gamma then case rule of
    NearestRule -> \position v -> nearest (paletteAt palettes position.x) v
    OrderedRule m -> \position v -> ordered (thresholdAt m position) (paletteAt palettes position.x) v
  else case rule of
    NearestRule -> \position v -> conversion.toLight (nearest (paletteAt palettes position.x) (conversion.fromLight v))
    OrderedRule m ->
      let
        lightPalettes = map (paletteInLight conversion) palettes
      in
        \position v -> ordered (thresholdAt m position) (paletteAt lightPalettes position.x) v
  where
  paletteAt cellPalettes x = case Array.index cellPalettes (x / cellWidth) of
    Just palette -> palette
    -- `stepRow` rejects a row of a different length before quantizing it,
    -- and the band's cells span the width of its rows.
    Nothing -> unsafeCrashWith "Puregrain.Cells.bandQuantize: pixel outside its band's cells - row width invariant violated"

-- | A cell's colors taken to light, in the same order, so that the line
-- | between them, along which `orderedInCell` measures, is a line of light.
paletteInLight :: Conversion RGB -> CellPalette -> CellPalette
paletteInLight conversion (CellPalette s) =
  if s.length2 == 0.0 then singleColor (conversion.toLight s.first)
  else colorPair (conversion.toLight s.first) (conversion.toLight s.second)

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

-- | The second color where the pixel's fraction of the way from the first
-- | to the second, along the line between them, is above `t`; else the
-- | first. Without a division, like `Puregrain.Ordered`: (v − first) ·
-- | direction > t · length². A fraction below 0 or above 1 thus counts
-- | as 0 or 1, since thresholds lie strictly between them.
ordered :: Number -> CellPalette -> RGB -> RGB
ordered t (CellPalette s) (RGB p) = case s.first of
  RGB a ->
    if s.length2 == 0.0 then s.first
    else if (p.r - a.r) * s.direction.r + (p.g - a.g) * s.direction.g + (p.b - a.b) * s.direction.b > t * s.length2 then s.second
    else s.first
