module Dither.Palette where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Maybe (Maybe)
import Data.Tuple (Tuple(..), fst)
import Dither.Pixel (RGB(..), Quantize, quantize)

-- | Squared Euclidean distance in RGB space — no need for the actual
-- | (more expensive) square root, since we only ever compare distances
-- | to find the minimum, and squaring is monotonic.
distance2 :: RGB -> RGB -> Number
distance2 (RGB a) (RGB b) =
  let dr = a.r - b.r
      dg = a.g - b.g
      db = a.b - b.b
  in dr * dr + dg * dg + db * db

-- | A palette, together with the distance metric to search it by,
-- | precomputed once and threaded through the hot path instead of
-- | being rebuilt/re-selected per pixel — same rationale as
-- | `CompiledKernel` in `Dither.Kernel`. Packing `distance` alongside
-- | `colors` (rather than passing it as a separate argument at every
-- | call site) is what lets `distance2` and a future `distance2Lab`
-- | (distance in CIELAB space) be swapped in interchangeably, without
-- | threading two parameters everywhere a palette is threaded today.
-- |
-- | `colors` is a `NonEmptyArray`, not `Array`: an empty palette has
-- | no nearest color, so this makes that case unrepresentable at the
-- | type level rather than a check `nearestColorFast` would otherwise
-- | have to make (and fail, or silently paper over) on every pixel.
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

-- Ready-made palettes (black/white, web-safe, CGA, ANSI, C64, ZX Spectrum)
-- live in `Dither.Palette.Presets`.
