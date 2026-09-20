module Dither.Pixel where

import Prelude

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
newtype Quantize a = Quantize (a -> a)

runQuantize :: forall a. Quantize a -> a -> a
runQuantize (Quantize f) = f    