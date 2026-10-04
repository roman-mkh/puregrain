-- | Dithering to a palette: each pixel becomes the nearest palette color,
-- | with all three channels chosen together. `nearestColor` is the ready
-- | quantizer; ready-made palettes (black and white, web-safe, CGA, ANSI,
-- | Commodore 64, ZX Spectrum) are in `Puregrain.Palette.Presets`.
-- |
-- | Distances are plain RGB distances, which aren't perceptual: pure green
-- | is nearer to black than to white.
module Puregrain.Palette
  ( CompiledPalette
  , compilePalette
  , compilePaletteFromArray
  , paletteColors
  , distance2
  , nearestColorFast
  , nearestColor
  ) where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Maybe (Maybe)
import Data.Tuple (Tuple(..), fst)
import Puregrain.Pixel (RGB(..))
import Puregrain.Quantize (Quantize, quantize)

-- | Squared Euclidean distance in RGB space — no need for the actual
-- | (more expensive) square root, since we only ever compare distances
-- | to find the minimum, and squaring is monotonic.
distance2 :: RGB -> RGB -> Number
distance2 (RGB a) (RGB b) =
  let dr = a.r - b.r
      dg = a.g - b.g
      db = a.b - b.b
  in dr * dr + dg * dg + db * db

-- | A palette together with the distance metric to search it by, built
-- | once per image rather than for every pixel. The metric travels with
-- | the colors, so another metric (such as a future distance in CIELAB
-- | space) can be swapped in without changing any signature.
-- |
-- | Opaque: build one with `compilePalette` or `compilePaletteFromArray`,
-- | read its colors with `paletteColors`. Its representation may change,
-- | for instance to make the search faster. The colors are never empty:
-- | an empty palette has no nearest color.
newtype CompiledPalette = CompiledPalette
  { colors   :: NonEmptyArray RGB
  , distance :: RGB -> RGB -> Number
  }

-- | Primary constructor. Total: a `NonEmptyArray` already proves the
-- | palette is non-empty at the type level, so there is nothing here
-- | that can fail at runtime.
compilePalette :: (RGB -> RGB -> Number) -> NonEmptyArray RGB -> CompiledPalette
compilePalette distance colors = CompiledPalette { colors, distance }

-- | Convenience constructor for a palette arriving as a plain `Array`
-- | — the common shape at an FFI/CLI/JSON boundary, where non-
-- | emptiness isn't yet proven at the type level. `Nothing` only for
-- | an empty `colors`; delegates to `compilePalette` otherwise.
compilePaletteFromArray :: (RGB -> RGB -> Number) -> Array RGB -> Maybe CompiledPalette
compilePaletteFromArray distance colors = compilePalette distance <$> NEA.fromArray colors

-- | The palette's colors, in the order they were given.
paletteColors :: CompiledPalette -> NonEmptyArray RGB
paletteColors (CompiledPalette p) = p.colors

-- | Snaps `pixel` to the nearest color in a `CompiledPalette`, by the
-- | distance metric it was compiled with. Each color's distance to
-- | `pixel` is computed exactly once (paired up before folding), not
-- | recomputed on every comparison the fold makes along the way.
nearestColorFast :: CompiledPalette -> RGB -> RGB
nearestColorFast (CompiledPalette p) pixel =
  fst (NEA.foldl1 closer (map (\c -> Tuple c (p.distance pixel c)) p.colors))
  where
  closer t1@(Tuple _ d1) t2@(Tuple _ d2) = if d1 <= d2 then t1 else t2

-- | Builds a Quantize that snaps every pixel to the nearest color in
-- | the given (non-empty) palette, by squared Euclidean distance.
nearestColor :: NonEmptyArray RGB -> Quantize RGB
nearestColor palette = quantize (nearestColorFast (compilePalette distance2 palette))

