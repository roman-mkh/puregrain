-- | Quantizers: the step of dithering that picks an output value for each
-- | pixel. A `Quantize a` gets the pixel's value, with the error diffused
-- | into it already added, and the pixel's position; `ditherImage` diffuses
-- | the difference between the two to the neighbours.
-- |
-- | Ready-made: `threshold` (1-bit), `nearestLevel` with `evenRamp` (a few
-- | levels), and `perChannel` to use either on every channel of a color
-- | pixel. Palettes are in `Puregrain.Palette`, ordered (Bayer) dithering
-- | in `Puregrain.Ordered`. Build your own with `quantize` (position-blind)
-- | or `quantizeWith` (uses the position), or with `quantizeInLight`, which
-- | decides in light when the dithering has a gamma
-- | (`Puregrain.Dither.ditherImageWith`).
module Puregrain.Quantize
  ( module Exports
  , quantize
  , quantizeWith
  , quantizeInLight
  , runQuantize
  , runQuantizeWith
  , perChannel
  , threshold
  , nearestLevel
  , evenRamp
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Int (toNumber)
import Data.Number (round)
import Data.Ord (abs)
import Data.Tuple (Tuple(..), fst)
import Partial.Unsafe (unsafePartial)
import Puregrain.Internal.Gamma (Gamma, conversionFor, isOff, noConversion, toLightValue)
import Puregrain.Internal.Quantize (Context, Quantize) as Exports
import Puregrain.Internal.Quantize (Context, Quantize(..), quantizerFor)
import Puregrain.Internal.Util (safeRange)
import Puregrain.Pixel (class ColorChannels, class MapChannels, mapChannels)

-- | A quantizer that ignores the pixel's position, the common case.
-- |
-- | - `a -> a`: from the corrected value to the output value.
-- |
-- | ```purescript
-- | -- 1-bit with the cut at 100
-- | quantize \v -> if v < 100.0 then 0.0 else 255.0
-- | ```
-- |
-- | With a gamma other than `gammaOff` (`Puregrain.Dither.ditherImageWith`),
-- | the function still gets and returns stored values: each pixel is
-- | brought back from light before it and its result taken to light after,
-- | while the error stays in light. That's two conversions per pixel; a
-- | quantizer built with `quantizeInLight` needs none.
quantize :: forall a. (a -> a) -> Quantize a
quantize f = Quantize \conversion ->
  if isOff conversion.gamma then \_ -> f
  else \_ x -> conversion.toLight (f (conversion.fromLight x))

-- | A quantizer that also gets the pixel's position: ordered or noise
-- | dithering, say, or a lookup in per-pixel data such as a mask.
-- |
-- | - `Context -> a -> a`: from the position and the corrected value to
-- |   the output value.
-- |
-- | ```purescript
-- | -- 1-bit with the cut at 64 and 192 in a checkerboard
-- | quantizeWith \{ x, y } v ->
-- |   if v < (if (x + y) `mod` 2 == 0 then 64.0 else 192.0) then 0.0 else 255.0
-- | ```
-- |
-- | With a gamma other than `gammaOff`, as for `quantize`: the function
-- | still sees stored values, at two conversions per pixel.
quantizeWith :: forall a. (Context -> a -> a) -> Quantize a
quantizeWith f = Quantize \conversion ->
  if isOff conversion.gamma then f
  else \context x -> conversion.toLight (f context (conversion.fromLight x))

-- | A quantizer that works in light, the way the ready-made ones are built.
-- |
-- | - `Gamma -> Context -> a -> a`: given the dithering's curve, prepares
-- |   what it needs, then returns the function for each pixel, which gets
-- |   the pixel's position and its corrected value in light, and returns
-- |   the output in light.
-- |
-- | The curve is `gammaOff` for `ditherImage`, where light and stored
-- | values are the same numbers, and the one given to `ditherImageWith`.
-- | Convert your own numbers with `Puregrain.Gamma.toLight` in a `let`
-- | outside the function for each pixel: there they're converted once per
-- | image, inside it once per pixel, since PureScript shares nothing by
-- | itself. An output that's the light of a whole number from 0 to 255 is
-- | written as exactly that number.
-- |
-- | ```purescript
-- | -- three tones: black, a mid gray, and white
-- | threeTones = quantizeInLight \gamma ->
-- |   let lo = toLight gamma 64.0
-- |       hi = toLight gamma 192.0
-- |       gray = toLight gamma 128.0
-- |   in \_ v -> if v < lo then 0.0 else if v < hi then gray else 255.0
-- | ```
quantizeInLight :: forall a. (Gamma -> Context -> a -> a) -> Quantize a
quantizeInLight f = Quantize \conversion -> f conversion.gamma

-- | Runs a quantizer.
-- |
-- | - `Quantize a`: the quantizer.
-- | - `Context`: the pixel's position.
-- | - `a`: the corrected value.
-- |
-- | Returns the output value. For many pixels, apply it to the quantizer
-- | once and keep the result, `let q = runQuantize quantizer`, then call
-- | `q` for each pixel: some quantizers prepare things first.
runQuantize :: forall a. Quantize a -> Context -> a -> a
runQuantize = quantizerFor noConversion

-- | Runs a quantizer as `ditherImageWith` does with a gamma, for a stored
-- | value.
-- |
-- | - `Gamma`: the curve.
-- | - `Quantize a`: the quantizer.
-- | - `Context`: the pixel's position.
-- | - `a`: the corrected value, as stored.
-- |
-- | Returns the output value, as stored: the value is taken to light, the
-- | quantizer decides there, and its output comes back. With `gammaOff`,
-- | the same as `runQuantize`. As with `runQuantize`, keep
-- | `runQuantizeWith gamma quantizer` for many pixels.
runQuantizeWith :: forall a. ColorChannels a => Gamma -> Quantize a -> Context -> a -> a
runQuantizeWith gamma q =
  let
    conversion = conversionFor gamma
    quantizer = quantizerFor conversion q
  in
    \context value -> conversion.fromLight (quantizer context (conversion.toLight value))

-- | Runs a one-channel quantizer on every channel of a pixel,
-- | independently, each with the pixel's position.
-- |
-- | - `a`: the pixel type, with `MapChannels`: `Number`, `RGB` or `RGBA`.
-- | - `Quantize Number`: the quantizer for one channel.
-- |
-- | Dithering an RGB image this way gives exactly what dithering its three
-- | channel planes separately would: a `Quantize Number` only ever sees
-- | one channel, so it can't couple them. For a quantizer that looks at
-- | the whole pixel, see `Puregrain.Palette.nearestColor`.
-- |
-- | ```purescript
-- | -- 4 levels per channel
-- | perChannel (nearestLevel (evenRamp 4)) :: Quantize RGB
-- | ```
perChannel :: forall a. MapChannels a => Quantize Number -> Quantize a
perChannel (Quantize q) = Quantize \conversion ->
  let
    -- the one-channel quantizer, resolved once with the curve's own
    -- conversion of single values
    channel = q (conversionFor conversion.gamma)
  in
    \context -> mapChannels (channel context)

-- | The classic 1-bit quantizer: 0 (black) below the threshold, 255
-- | (white) at or above it.
-- |
-- | - `Number`: the threshold, usually 128.
-- |
-- | `nearestLevel (evenRamp 2)` is the same with the cut fixed at 127.5.
-- |
-- | With a gamma (`ditherImageWith`), the cut stays at the stored value:
-- | it's converted to light once, so a gray below it still goes to black.
threshold :: Number -> Quantize Number
threshold t = quantizeInLight \gamma ->
  let
    cut = toLightValue gamma t
  in
    \_ x -> if x < cut then 0.0 else 255.0

-- | Snaps a value to the nearest of the given levels: the one-channel
-- | sibling of `Puregrain.Palette.nearestColor`.
-- |
-- | - `NonEmptyArray Number`: the levels, in any order; on an exact tie,
-- |   the earlier wins.
-- |
-- | Values below the lowest level snap to it, values above the highest to
-- | that one.
-- |
-- | ```purescript
-- | nearestLevel (evenRamp 4)   -- 0, 85, 170 or 255
-- | ```
-- |
-- | With a gamma (`ditherImageWith`), a value still takes the level
-- | nearest on stored values, while the error stays in light. Levels that
-- | aren't whole numbers are rounded first (`evenRamp 3`'s 127.5 to 128),
-- | so that every level comes back exactly.
--
-- With a curve, the cut between two neighbouring levels is their midpoint
-- on stored values, converted to light once; with gammaOff, today's scan.
--
-- Each level's distance is computed once, paired up before the fold.
--
-- TODO(benchmark): this is an O(N) linear scan per pixel. `Number` has a
-- total order (unlike RGB), so sorting `levels` once and binary-searching
-- would be O(log N) — deliberately not done yet: at realistic N (2-16)
-- the difference should be negligible, and it would add a sortedness
-- invariant to maintain. Measured 2026-10-04: `--levels 4` costs ×1.13
-- of a plain threshold (docs/benchmarks-dithering.md). Benchmark again
-- before changing it.
nearestLevel :: NonEmptyArray Number -> Quantize Number
nearestLevel levels = quantizeInLight \gamma ->
  if isOff gamma then \_ x -> fst (NEA.foldl1 closer (map (\l -> Tuple l (abs (x - l))) levels))
  else
    let
      nearest = nearestInLight gamma levels
    in
      \_ x -> nearest x
  where
  closer t1@(Tuple _ d1) t2@(Tuple _ d2) = if d1 <= d2 then t1 else t2

-- The levels rounded to whole bytes and sorted, each with its place in
-- the given order; the cut between two neighbours is their midpoint on
-- stored values, converted to light once. A value exactly at a cut takes
-- the level given earlier, as the scan with `gammaOff` does.
nearestInLight :: Gamma -> NonEmptyArray Number -> Number -> Number
nearestInLight gamma levels =
  let
    sorted = Array.sortBy (comparing _.stored <> comparing _.index)
      (Array.mapWithIndex (\index level -> { stored: round level, index }) (NEA.toArray levels))
    lights = map (\level -> toLightValue gamma level.stored) sorted
    cuts = Array.zipWith
      (\a b -> { at: toLightValue gamma ((a.stored + b.stored) / 2.0), upperFirst: b.index < a.index })
      sorted
      (Array.drop 1 sorted)
    count = Array.length cuts
    lightAt i = unsafePartial (Array.unsafeIndex lights i)
    cutAt i = unsafePartial (Array.unsafeIndex cuts i)
    pick x i =
      if i >= count then lightAt i
      else
        let
          cut = cutAt i
        in
          if x < cut.at || (x == cut.at && not cut.upperFirst) then lightAt i
          else pick x (i + 1)
  in
    \x -> pick x 0

-- | Evenly spaced levels from 0 to 255, both ends included, for
-- | `nearestLevel`.
-- |
-- | - `Int`: how many; 1 or less gives the single midpoint, 127.5.
-- |
-- | `evenRamp 2 == [0.0, 255.0]`, `evenRamp 4 == [0.0, 85.0, 170.0, 255.0]`.
-- One level has no "evenly spaced" positions, and the result can't be
-- empty, hence the midpoint for `n <= 1`.
evenRamp :: Int -> NonEmptyArray Number
evenRamp n
  | n <= 1 = NEA.singleton 127.5
  | otherwise = NEA.cons' 0.0 (map level (safeRange 1 (n - 1)))
  where
  level i = 255.0 * toNumber i / toNumber (n - 1)