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

-- | The squared distance between two colors in RGB, the usual metric for
-- | palettes: (r₁ − r₂)² + (g₁ − g₂)² + (b₁ − b₂)². Squared, since finding
-- | the nearest color only compares distances.
distance2 :: RGB -> RGB -> Number
distance2 (RGB a) (RGB b) =
  let dr = a.r - b.r
      dg = a.g - b.g
      db = a.b - b.b
  in dr * dr + dg * dg + db * db

-- | A palette ready to search: its colors, never empty, and the distance
-- | to search them by. Build it once per image with `compilePalette` or
-- | `compilePaletteFromArray`; read its colors with `paletteColors`.
-- | Opaque, so its representation may change, to make the search faster,
-- | say.
-- The metric travels with the colors, so another one, such as a distance
-- in CIELAB, can be swapped in without changing any signature.
newtype CompiledPalette = CompiledPalette
  { colors   :: NonEmptyArray RGB
  , distance :: RGB -> RGB -> Number
  }

-- | Makes a palette ready to search.
-- |
-- | - `RGB -> RGB -> Number`: the distance between a pixel and a color,
-- |   usually `distance2`.
-- | - `NonEmptyArray RGB`: the colors.
-- |
-- | ```purescript
-- | palette = compilePalette distance2 websafe216
-- | ```
compilePalette :: (RGB -> RGB -> Number) -> NonEmptyArray RGB -> CompiledPalette
compilePalette distance colors = CompiledPalette { colors, distance }

-- | As `compilePalette`, for colors in a plain `Array`, as they come from
-- | JSON or JavaScript, say.
-- |
-- | - `RGB -> RGB -> Number`: the distance, usually `distance2`.
-- | - `Array RGB`: the colors.
-- |
-- | `Nothing` for an empty array.
compilePaletteFromArray :: (RGB -> RGB -> Number) -> Array RGB -> Maybe CompiledPalette
compilePaletteFromArray distance colors = compilePalette distance <$> NEA.fromArray colors

-- | The palette's colors, in the order they were given.
paletteColors :: CompiledPalette -> NonEmptyArray RGB
paletteColors (CompiledPalette p) = p.colors

-- | The palette's color nearest to a pixel, by the palette's distance; on
-- | a tie, the earlier color. For many pixels, compile the palette once;
-- | `nearestColor` does that for you.
-- |
-- | - `CompiledPalette`: the palette.
-- | - `RGB`: the pixel.
-- Each color's distance is computed once, paired up before the fold.
nearestColorFast :: CompiledPalette -> RGB -> RGB
nearestColorFast (CompiledPalette p) pixel =
  fst (NEA.foldl1 closer (map (\c -> Tuple c (p.distance pixel c)) p.colors))
  where
  closer t1@(Tuple _ d1) t2@(Tuple _ d2) = if d1 <= d2 then t1 else t2

-- | A quantizer that turns each pixel into the nearest palette color, all
-- | three channels together, by `distance2`; on a tie, the earlier color.
-- |
-- | - `NonEmptyArray RGB`: the palette, e.g. from
-- |   `Puregrain.Palette.Presets`.
-- |
-- | ```purescript
-- | ditherImage floydSteinberg (nearestColor websafe216) image
-- | ```
nearestColor :: NonEmptyArray RGB -> Quantize RGB
nearestColor palette = quantize (nearestColorFast (compilePalette distance2 palette))

