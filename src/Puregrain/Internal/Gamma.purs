-- | The light curves behind `Puregrain.Gamma`, on single values on the
-- | 0–255 scale. Internal: may change without notice. Why the curves are
-- | built from exact operations only, and how: docs/exact-arithmetic.md.
module Puregrain.Internal.Gamma
  ( Gamma(..)
  , CurveParts
  , Conversion
  , noConversion
  , conversionFor
  , isOff
  , curve
  , off
  , power1p2
  , power1p5
  , power1p8
  , srgb
  , toLightValue
  , fromLightValue
  , toLightFormula
  , fromLightFormula
  , lightTable
  ) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Int (floor, toNumber)
import Data.Lazy (Lazy, defer, force)
import Data.Number (sqrt)
import Partial.Unsafe (unsafePartial)

import Puregrain.Internal.Exact (cubeRoot, fifthRoot)
import Puregrain.Pixel (class ColorChannels, mapColorChannels)

-- | A curve between a picture's stored values and light: one of
-- | `Puregrain.Gamma`'s presets, `gammaOff`, `gamma1p2`, `gamma1p5`,
-- | `gamma1p8` and `gammaSrgb`.
-- `Off` is the identity; a `Curve` has its two formulas and the light of
-- the 256 bytes, built the first time it's needed. (The comment above is
-- what Pursuit shows, through `Puregrain.Gamma`'s re-export.)
data Gamma = Off | Curve CurveParts

type CurveParts =
  { toLight :: Number -> Number
  , fromLight :: Number -> Number
  , table :: Lazy (Array Number)
  }

-- | What a driver hands a quantizer: a pixel type's two conversions, and
-- | the curve itself, for quantizers of single channels (`perChannel`).
type Conversion a =
  { toLight :: a -> a
  , fromLight :: a -> a
  , gamma :: Gamma
  }

-- | No conversion, for `gammaOff`: the drivers and the quantizers check
-- | `isOff` once per run and then skip converting altogether, so the
-- | identities here are never called per pixel.
noConversion :: forall a. Conversion a
noConversion = { toLight: identity, fromLight: identity, gamma: Off }

-- | The conversion of a pixel type's color channels by a curve.
conversionFor :: forall a. ColorChannels a => Gamma -> Conversion a
conversionFor Off = noConversion
conversionFor gamma = { toLight: mapColorChannels (toLightValue gamma), fromLight: mapColorChannels (fromLightValue gamma), gamma }

-- | Whether the curve is `Off`, the identity.
isOff :: Gamma -> Boolean
isOff Off = true
isOff _ = false

-- | A curve from its two formulas on the 0–1 scale, defined for 0 and up:
-- | scaled to 0–255 and mirrored for negative values, f(-v) = -f(v), as the
-- | W3C's sample code (CSS Color 4) extends sRGB's.
curve :: (Number -> Number) -> (Number -> Number) -> Gamma
curve to back = Curve { toLight, fromLight: scaled back, table: defer \_ -> map (toLight <<< toNumber) (0 .. 255) }
  where
  toLight = scaled to

scaled :: (Number -> Number) -> Number -> Number
scaled f v =
  if v < 0.0 then negate (scaled f (negate v))
  else 255.0 * f (v / 255.0)

off :: Gamma
off = Off

-- The power curves: light = x^γ, and back x = light^(1/γ), from the roots
-- of Puregrain.Internal.Exact and the square root, which ECMA-262 defines
-- exactly. The order of operations is part of the result: changed, it
-- would change the self-check's digest.

-- | x^1.2 = x · ⁵√x; back, L^(5/6) = √L · ∛L.
power1p2 :: Gamma
power1p2 = curve (\x -> x * fifthRoot x) (\l -> sqrt l * cubeRoot l)

-- | x^1.5 = x · √x; back, L^(2/3) = (∛L)².
power1p5 :: Gamma
power1p5 = curve (\x -> x * sqrt x) (\l -> let c = cubeRoot l in c * c)

-- | x^1.8 = x · (⁵√x)⁴; back, L^(5/9) = (∛(∛L))⁵.
power1p8 :: Gamma
power1p8 = curve to back
  where
  to x = let f = fifthRoot x in let f2 = f * f in x * (f2 * f2)
  back l = let c = cubeRoot (cubeRoot l) in let c2 = c * c in c2 * c2 * c

-- | sRGB's curve (IEC 61966-2-1): a straight piece near black, then a
-- | power of 2.4 with an offset. x^2.4 = x² · (⁵√x)²; back,
-- | L^(5/12) = √√L · √∛L.
srgb :: Gamma
srgb = curve to back
  where
  to c =
    if c <= 0.04045 then c / 12.92
    else let x = (c + 0.055) / 1.055 in let f = fifthRoot x in x * x * (f * f)
  back l =
    if l <= 0.0031308 then 12.92 * l
    else 1.055 * (sqrt (sqrt l) * sqrt (cubeRoot l)) - 0.055

-- | A value's light: a byte's from the table, any other value's from the
-- | formula (the table holds the formula's results, so both agree).
toLightValue :: Gamma -> Number -> Number
toLightValue Off v = v
toLightValue (Curve c) v = case byteOf v of
  true -> tableAt (force c.table) (floor v)
  false -> c.toLight v

-- | A light value back to a stored one, for what's written: the light of a
-- | byte gives that byte exactly, found in the table; any other value goes
-- | through the formula.
fromLightValue :: Gamma -> Number -> Number
fromLightValue Off l = l
fromLightValue (Curve c) l =
  let
    table = force c.table
    i = searchTable table l
  in
    if tableAt table i == l then toNumber i else c.fromLight l

-- | The formula to light, without the table.
toLightFormula :: Gamma -> Number -> Number
toLightFormula Off v = v
toLightFormula (Curve c) v = c.toLight v

-- | The formula back, without the table: for the self-check and the
-- | tests. The dithering's comparisons use `fromLightValue`, table first,
-- | so that a byte's light comes back as exactly that byte.
fromLightFormula :: Gamma -> Number -> Number
fromLightFormula Off l = l
fromLightFormula (Curve c) l = c.fromLight l

-- | The light of the 256 bytes; for `Off`, the bytes themselves.
lightTable :: Gamma -> Array Number
lightTable Off = map toNumber (0 .. 255)
lightTable (Curve c) = force c.table

byteOf :: Number -> Boolean
byteOf v = v >= 0.0 && v <= 255.0 && toNumber (floor v) == v

tableAt :: Array Number -> Int -> Number
tableAt table i = unsafePartial (Array.unsafeIndex table i)

-- The first byte whose light isn't below `l`, by halving 0–255 (the table
-- rises strictly), or 255 if every byte's light is below it.
searchTable :: Array Number -> Number -> Int
searchTable table l = go 0 255
  where
  go lo hi =
    if lo >= hi then lo
    else
      let mid = (lo + hi) / 2
      in if tableAt table mid < l then go (mid + 1) hi else go lo mid
