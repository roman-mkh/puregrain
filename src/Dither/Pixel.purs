module Dither.Pixel where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Int (toNumber)
import Data.Ord (abs)
import Data.Tuple (Tuple(..), fst)
import Dither.Util (safeRange)

-- | Single-channel pixel value (grayscale). A plain alias for `Number` —
-- | no wrapper, so existing scalar code keeps working unchanged.
type Gray = Number

class Ring a <= Scalable a where
  -- | Multiplies every channel of `a` by a plain `Number` weight. Kernel
  -- | weights are always `Number` regardless of how many channels `a`
  -- | has, so this is deliberately NOT `a -> a -> a` — it's a separate
  -- | operation from `Ring`'s own `mul`.
  scale :: Number -> a -> a

instance Scalable Number where
  scale w x = w * x

newtype RGB = RGB { r :: Number, g :: Number, b :: Number }

-- | Needed for tests (`===`/`shouldEqual` on RGB values, e.g. in
-- | `Test.Dither.PaletteSpec`) — delegates to the record's own
-- | automatic Eq/Show instances, no hand-written comparison/rendering.
derive newtype instance Eq RGB
derive newtype instance Show RGB

instance Semiring RGB where
  add (RGB a) (RGB b) = RGB { r: a.r + b.r, g: a.g + b.g, b: a.b + b.b }
  zero = RGB { r: 0.0, g: 0.0, b: 0.0 }
  mul (RGB a) (RGB b) = RGB { r: a.r * b.r, g: a.g * b.g, b: a.b * b.b }
  one = RGB { r: 1.0, g: 1.0, b: 1.0 }

instance Ring RGB where
  sub (RGB a) (RGB b) = RGB { r: a.r - b.r, g: a.g - b.g, b: a.b - b.b }

instance Scalable RGB where
  scale w (RGB p) = RGB { r: w * p.r, g: w * p.g, b: w * p.b }

newtype RGBA = RGBA { r :: Number, g :: Number, b :: Number, a :: Number }

instance Semiring RGBA where
  add (RGBA x) (RGBA y) = RGBA { r: x.r + y.r, g: x.g + y.g, b: x.b + y.b, a: x.a + y.a }
  zero = RGBA { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }
  mul (RGBA x) (RGBA y) = RGBA { r: x.r * y.r, g: x.g * y.g, b: x.b * y.b, a: x.a * y.a }
  one = RGBA { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }

instance Ring RGBA where
  sub (RGBA x) (RGBA y) = RGBA { r: x.r - y.r, g: x.g - y.g, b: x.b - y.b, a: x.a - y.a }

instance Scalable RGBA where
  scale w (RGBA p) = RGBA { r: w * p.r, g: w * p.g, b: w * p.b, a: w * p.a }

-- | Applies one `Number -> Number` function to every channel of `a`,
-- | independently — the building block for scalarED (see `perChannel`,
-- | and "scalarED / vectorED" in CLAUDE.md). Expected laws, as for any
-- | Functor-like mapping:
-- |
-- |   mapChannels identity      == identity
-- |   mapChannels (f <<< g)     == mapChannels f <<< mapChannels g
-- |
-- | Deliberately separate from `Scalable` for now, even though
-- | `scale w == mapChannels (w * _)` for every instance here: `Scalable`
-- | is what the diffusion core needs, `MapChannels` is only what
-- | quantizer construction needs, and folding one into the other is
-- | easy later if that split turns out not to earn its keep.
class MapChannels a where
  mapChannels :: (Number -> Number) -> a -> a

-- | A single-channel pixel is its own only channel — so `perChannel` on
-- | `Gray`/`Number` is just the quantizer itself, unchanged.
instance MapChannels Number where
  mapChannels f x = f x

instance MapChannels RGB where
  mapChannels f (RGB p) = RGB { r: f p.r, g: f p.g, b: f p.b }

-- | Alpha is mapped too, like every other channel — consistent with
-- | RGBA's `Ring`/`Scalable` instances, which diffuse alpha error too.
instance MapChannels RGBA where
  mapChannels f (RGBA p) = RGBA { r: f p.r, g: f p.g, b: f p.b, a: f p.a }

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
-- | applying it to every channel independently — scalarED (see
-- | "scalarED / vectorED" in CLAUDE.md). The type is the guarantee: a
-- | `Quantize Number` only ever sees one channel's value, so it cannot
-- | couple channels together, by construction rather than by
-- | convention. (It also gets the pixel's position — the same one for
-- | every channel.) The result is an ordinary `Quantize a`, fed to the
-- | unmodified `ditherImage` — no separate scalarED pipeline exists.
-- |
-- | (vectorED is the other case: write a `Quantize a` directly on the
-- | whole pixel, e.g. `Dither.Palette.nearestColor`.)
perChannel :: forall a. MapChannels a => Quantize Number -> Quantize a
perChannel (Quantize q) = Quantize \ctx -> mapChannels (q ctx)

-- | The classic 1-bit quantizer: values below `t` become 0.0 (black),
-- | values at or above it become 255.0 (white). `nearestLevel (evenRamp
-- | 2)` is the same idea with the cut fixed halfway, at 127.5; this one
-- | makes the cut point adjustable. Total for any input.
threshold :: Number -> Quantize Number
threshold t = quantize \x -> if x < t then 0.0 else 255.0

-- | Builds a Quantize that snaps a value to the nearest of the given
-- | levels — the 1D sibling of `Dither.Palette.nearestColor`, with the
-- | same shape and the same behavior: each level's distance is computed
-- | exactly once (paired up before folding), and an exact tie goes to
-- | the level that comes earlier in `levels`. `levels` need not be
-- | sorted. Total for any input, including the out-of-range values
-- | diffusion routinely produces: anything below the lowest level snaps
-- | to it, anything above the highest snaps to that.
-- |
-- | TODO(benchmark): this is an O(N) linear scan per pixel. `Number`
-- | has a total order (unlike RGB), so sorting `levels` once and
-- | binary-searching would be O(log N) — deliberately not done yet: at
-- | realistic N (2–16) the difference should be negligible, and it
-- | would add a sortedness invariant to maintain. Measured 2026-09-25:
-- | `--levels 4` costs ×1.06 of a plain threshold, so the scan is a small
-- | share of the time (docs/benchmarks-dithering.md). Benchmark again
-- | before changing it.
nearestLevel :: NonEmptyArray Number -> Quantize Number
nearestLevel levels = quantize \x ->
  fst (NEA.foldl1 closer (map (\l -> Tuple l (abs (x - l))) levels))
  where
  closer t1@(Tuple _ d1) t2@(Tuple _ d2) = if d1 <= d2 then t1 else t2

-- | `n` evenly spaced levels across [0, 255] (this project's channel-
-- | value convention), both ends included — e.g. `evenRamp 2 ==
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