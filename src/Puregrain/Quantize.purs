-- | Quantizers: the step of dithering that picks an output value for each
-- | pixel. A `Quantize a` gets the pixel's value, with the error diffused
-- | into it already added, and the pixel's position; `ditherImage` diffuses
-- | the difference between the two to the neighbours.
-- |
-- | Ready-made: `threshold` (1-bit), `nearestLevel` with `evenRamp` (a few
-- | levels), and `perChannel` to use either on every channel of a color
-- | pixel. Palettes are in `Puregrain.Palette`, ordered (Bayer) dithering
-- | in `Puregrain.Ordered`.
module Puregrain.Quantize
  ( Quantize(..)
  , Context
  , quantize
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

-- | A quantization function: given a pixel value with accumulated
-- | diffused error already applied ("corrected"), returns the quantized
-- | value to both output and use in further error calculation.
-- |
-- | Must be total and defined for the full range of `a` a diffusion
-- | process can produce, not just the "natural" range of an unmodified
-- | pixel: accumulated error routinely pushes `corrected` outside a
-- | pixel's nominal bounds (e.g. below 0 or above 255 for an 8-bit
-- | channel) before this function sees it, and it must still return a
-- | sensible in-range result.
-- |
-- | It also receives the pixel's position (`Context`), for quantizers
-- | whose decision depends on where the pixel is — ordered (Bayer)
-- | dithering, seeded noise. Most don't care: build those with `quantize`,
-- | which ignores the position.
newtype Quantize a = Quantize (Context -> a -> a)

-- | Where the pixel being quantized sits: column `x` and row `y`, both
-- | counted from 0 at the top-left. A record so it can grow (e.g. a seed)
-- | without breaking quantizers: helpers that need only some fields can
-- | take `forall r. { x :: Int, y :: Int | r }` and keep compiling.
type Context = { x :: Int, y :: Int }

-- | A quantizer that ignores the pixel's position — the common case.
quantize :: forall a. (a -> a) -> Quantize a
quantize f = Quantize \_ -> f

runQuantize :: forall a. Quantize a -> Context -> a -> a
runQuantize (Quantize f) = f

-- | Lifts a single-channel quantizer to a multi-channel pixel type,
-- | applying it to every channel independently. The type is the
-- | guarantee: a `Quantize Number` only ever sees one channel's value, so
-- | it cannot couple channels together, by construction rather than by
-- | convention. (It also gets the pixel's position, the same one for every
-- | channel.) The result is an ordinary `Quantize a` for `ditherImage`:
-- | dithering an RGB image this way gives exactly what dithering its three
-- | channel planes separately would.
-- |
-- | (The other case is a quantizer that looks at the whole pixel, e.g.
-- | `Puregrain.Palette.nearestColor`.)
perChannel :: forall a. MapChannels a => Quantize Number -> Quantize a
perChannel (Quantize q) = Quantize \ctx -> mapChannels (q ctx)

-- | The classic 1-bit quantizer: values below `t` become 0.0 (black),
-- | values at or above it become 255.0 (white). `nearestLevel (evenRamp
-- | 2)` is the same idea with the cut fixed halfway, at 127.5; this one
-- | makes the cut point adjustable. Total for any input.
threshold :: Number -> Quantize Number
threshold t = quantize \x -> if x < t then 0.0 else 255.0

-- | Builds a Quantize that snaps a value to the nearest of the given
-- | levels — the 1D sibling of `Puregrain.Palette.nearestColor`, with the
-- | same shape and the same behavior: each level's distance is computed
-- | exactly once (paired up before folding), and an exact tie goes to
-- | the level that comes earlier in `levels`. `levels` need not be
-- | sorted. Total for any input, including the out-of-range values
-- | diffusion routinely produces: anything below the lowest level snaps
-- | to it, anything above the highest snaps to that.
--
-- TODO(benchmark): this is an O(N) linear scan per pixel. `Number` has a
-- total order (unlike RGB), so sorting `levels` once and binary-searching
-- would be O(log N) — deliberately not done yet: at realistic N (2–16)
-- the difference should be negligible, and it would add a sortedness
-- invariant to maintain. Measured 2026-10-04: `--levels 4` costs ×1.13
-- of a plain threshold (docs/benchmarks-dithering.md). Benchmark again
-- before changing it.
nearestLevel :: NonEmptyArray Number -> Quantize Number
nearestLevel levels = quantize \x ->
  fst (NEA.foldl1 closer (map (\l -> Tuple l (abs (x - l))) levels))
  where
  closer t1@(Tuple _ d1) t2@(Tuple _ d2) = if d1 <= d2 then t1 else t2

-- | `n` evenly spaced levels across [0, 255] (the channel-value
-- | convention of this library), both ends included — e.g. `evenRamp 2 ==
-- | [0.0, 255.0]` (black/white), `evenRamp 4 == [0.0, 85.0, 170.0,
-- | 255.0]`. Meant to be used as `nearestLevel (evenRamp n)`.
-- |
-- | "Evenly spaced" has no meaning for a single point, so `n <= 1`
-- | (including zero and negative `n`) collapses to one midpoint level,
-- | `[127.5]` — the result is a `NonEmptyArray`, so there must always be
-- | at least one level to return.
evenRamp :: Int -> NonEmptyArray Number
evenRamp n
  | n <= 1 = NEA.singleton 127.5
  | otherwise = NEA.cons' 0.0 (map level (safeRange 1 (n - 1)))
  where
  level i = 255.0 * toNumber i / toNumber (n - 1)