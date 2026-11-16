-- | How a picture's stored numbers turn into light, for dithering that keeps
-- | the amount of light rather than the average of the numbers.
-- |
-- | A gamma here doesn't adjust the picture, as an image editor's gamma
-- | slider does: it says how the screen turns the numbers into light, and
-- | the dithering then keeps that light. `gammaOff`, the default, converts
-- | nothing, as dithering always has; `gammaSrgb` is linear light, the sRGB
-- | standard's own curve; `gamma1p2`, `gamma1p5` and `gamma1p8` lie between.
-- | Which value for which view, measured:
-- | [docs/gamma.md](https://github.com/roman-mkh/puregrain/blob/master/docs/gamma.md).
-- |
-- | The curves are computed from exact arithmetic only, so they give the
-- | same results on every JavaScript engine; why and how:
-- | [docs/exact-arithmetic.md](https://github.com/roman-mkh/puregrain/blob/master/docs/exact-arithmetic.md).
module Puregrain.Gamma
  ( module Exports
  , gammaOff
  , gamma1p2
  , gamma1p5
  , gamma1p8
  , gammaSrgb
  , toLight
  , fromLight
  , toGray
  ) where

import Prelude

import Puregrain.Internal.Gamma (Gamma) as Exports
import Puregrain.Internal.Gamma (Gamma, fromLightValue, isOff, toLightValue)
import Puregrain.Internal.Gamma as Internal
import Puregrain.Pixel (class ColorChannels, RGB(..), mapColorChannels)

-- | No conversion: the stored numbers are taken as amounts of light, as
-- | dithering has always taken them. The default.
gammaOff :: Gamma
gammaOff = Internal.off

-- | A power curve: light = (value / 255)^1.2 × 255.
gamma1p2 :: Gamma
gamma1p2 = Internal.power1p2

-- | A power curve: light = (value / 255)^1.5 × 255.
gamma1p5 :: Gamma
gamma1p5 = Internal.power1p5

-- | A power curve: light = (value / 255)^1.8 × 255, the gamma of Apple
-- | RGB, the classic Macintosh's color space.
gamma1p8 :: Gamma
gamma1p8 = Internal.power1p8

-- | Linear light: the sRGB standard's curve (IEC 61966-2-1), a straight
-- | piece near black and a power of 2.4 above it, which behaves much like a
-- | power of 2.2 overall.
gammaSrgb :: Gamma
gammaSrgb = Internal.srgb

-- | Converts a pixel's color channels from stored values to light, on the
-- | same 0–255 scale, leaving alpha as it is.
-- |
-- | - `Gamma`: the curve.
-- | - `a`: the pixel, as stored.
-- |
-- | Returns the pixel in light. A whole number from 0 to 255 gets its light
-- | from a table built once per curve, the first time it's needed; other
-- | values from the curve's formula, with the same results. A negative
-- | value gets the negative of its magnitude's light.
-- |
-- | ```purescript
-- | toLight gammaSrgb 128.0   -- 55.04…, 21.6% of white's light
-- | toLight gammaOff 128.0    -- 128.0
-- | ```
toLight :: forall a. ColorChannels a => Gamma -> a -> a
toLight gamma = mapColorChannels (toLightValue gamma)

-- | Converts a pixel's color channels from light back to stored values,
-- | leaving alpha as it is.
-- |
-- | - `Gamma`: the curve.
-- | - `a`: the pixel, in light.
-- |
-- | Returns the pixel as stored. The light of a whole number from 0 to 255
-- | gives that number back exactly, so a palette's colors and a ramp's
-- | levels come back as they were; other values go through the curve's
-- | formula.
-- |
-- | ```purescript
-- | fromLight gammaSrgb (toLight gammaSrgb 85.0)   -- 85.0, exactly
-- | ```
fromLight :: forall a. ColorChannels a => Gamma -> a -> a
fromLight gamma = mapColorChannels (fromLightValue gamma)

-- | A color's gray, for dithering a color picture in gray.
-- |
-- | - `Gamma`: the curve, which decides the formula; give the dithering
-- |   the same one.
-- | - `RGB`: the color, as stored.
-- |
-- | Returns the gray as a stored value, 0 to 255. A neutral color, with
-- | red, green and blue equal, gives exactly that value. With `gammaOff`,
-- | the gray is luma, 0.299 R + 0.587 G + 0.114 B on the stored values, the
-- | classic conversion. With a curve, it's the gray that gives off as much
-- | light as the color: 0.2126 R + 0.7152 G + 0.0722 B on the channels'
-- | light (luminance, with `gammaSrgb`), brought back to a stored value.
-- | Saturated colors then come out lighter than with luma, pure blue 76
-- | instead of 29 with `gammaSrgb`; natural colors such as skin barely
-- | change.
-- |
-- | ```purescript
-- | toGray gammaOff (RGB { r: 0.0, g: 0.0, b: 255.0 })    -- 29.07
-- | toGray gammaSrgb (RGB { r: 0.0, g: 0.0, b: 255.0 })   -- 75.96…
-- |
-- | ditherImageWith gammaSrgb floydSteinberg (threshold 128.0)
-- |   (map (map (toGray gammaSrgb)) image)
-- | ```
-- The neutral case first: the weights add up to 1, but in floating point
-- their sum with three equal values isn't always that value (65 of the
-- 256 bytes for luma, 79 in sRGB's light). The order of operations is
-- part of the result, as in the curves.
toGray :: Gamma -> RGB -> Number
toGray gamma (RGB p) =
  if p.r == p.g && p.g == p.b then p.r
  else if isOff gamma then 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
  else fromLightValue gamma (0.2126 * toLightValue gamma p.r + 0.7152 * toLightValue gamma p.g + 0.0722 * toLightValue gamma p.b)
