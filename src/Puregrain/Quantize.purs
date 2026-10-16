-- | Quantizers: the step of dithering that picks an output value for each
-- | pixel. A `Quantize a` gets the pixel's value, with the error diffused
-- | into it already added, and the pixel's position; `ditherImage` diffuses
-- | the difference between the two to the neighbours.
-- |
-- | Ready-made: `threshold` (1-bit), `nearestLevel` with `evenRamp` (a few
-- | levels), and `perChannel` to use either on every channel of a color
-- | pixel. Palettes are in `Puregrain.Palette`, ordered (Bayer) dithering
-- | in `Puregrain.Ordered`. Build your own with `quantize` (position-blind)
-- | or `quantizeWith` (uses the position).
module Puregrain.Quantize
  ( Quantize
  , Context
  , quantize
  , quantizeWith
  , runQuantize
  , perChannel
  , threshold
  , nearestLevel
  , evenRamp
  ) where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Int (toNumber)
import Data.Ord (abs)
import Data.Tuple (Tuple(..), fst)
import Puregrain.Internal.Util (safeRange)
import Puregrain.Pixel (class MapChannels, mapChannels)

-- | A quantizer: picks a pixel's output value; `a` is the pixel type.
-- | Build one with `quantize`, or `quantizeWith` when the decision depends
-- | on the pixel's position; run one with `runQuantize`. Opaque, so its
-- | representation can change without breaking anyone.
-- |
-- | It gets the pixel's corrected value, with the error diffused into it
-- | already added, and must be total: accumulated error pushes values
-- | beyond the nominal range, below 0 or above 255, and the quantizer must
-- | still return a sensible value. `ditherImage` diffuses the difference
-- | between the corrected value and the output to the neighbours.
newtype Quantize a = Quantize (Context -> a -> a)

-- | Where the pixel being quantized sits: column `x` and row `y`, from 0
-- | at the top-left. A record so it can grow, with a seed say, without
-- | breaking quantizers: a helper that needs only some fields can take
-- | `forall r. { x :: Int, y :: Int | r }`.
type Context = { x :: Int, y :: Int }

-- | A quantizer that ignores the pixel's position, the common case.
-- |
-- | - `a -> a`: from the corrected value to the output value.
-- |
-- | ```purescript
-- | -- 1-bit with the cut at 100
-- | quantize \v -> if v < 100.0 then 0.0 else 255.0
-- | ```
quantize :: forall a. (a -> a) -> Quantize a
quantize f = Quantize \_ -> f

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
quantizeWith :: forall a. (Context -> a -> a) -> Quantize a
quantizeWith = Quantize

-- | Runs a quantizer.
-- |
-- | - `Quantize a`: the quantizer.
-- | - `Context`: the pixel's position.
-- | - `a`: the corrected value.
-- |
-- | Returns the output value.
runQuantize :: forall a. Quantize a -> Context -> a -> a
runQuantize (Quantize f) = f

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
perChannel (Quantize q) = Quantize \ctx -> mapChannels (q ctx)

-- | The classic 1-bit quantizer: 0 (black) below the threshold, 255
-- | (white) at or above it.
-- |
-- | - `Number`: the threshold, usually 128.
-- |
-- | `nearestLevel (evenRamp 2)` is the same with the cut fixed at 127.5.
threshold :: Number -> Quantize Number
threshold t = quantize \x -> if x < t then 0.0 else 255.0

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
nearestLevel levels = quantize \x ->
  fst (NEA.foldl1 closer (map (\l -> Tuple l (abs (x - l))) levels))
  where
  closer t1@(Tuple _ d1) t2@(Tuple _ d2) = if d1 <= d2 then t1 else t2

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