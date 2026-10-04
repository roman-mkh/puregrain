-- | Pixel types: a single gray channel (`Gray`, a plain `Number`), `RGB`
-- | and `RGBA`, with channel values on the 0–255 scale by convention.
-- |
-- | Error diffusion adds and subtracts error, so a pixel type must be a
-- | `Ring`, and `Scalable` by the kernel's `Number` weights. `MapChannels`
-- | lets a one-channel quantizer work on every channel of a pixel (see
-- | `Puregrain.Quantize.perChannel`).
module Puregrain.Pixel
  ( Gray
  , RGB(..)
  , RGBA(..)
  , class Scalable
  , scale
  , class MapChannels
  , mapChannels
  ) where

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

-- | Compared and shown like the record inside.
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
-- | independently: the building block for dithering each channel on its
-- | own (see `Puregrain.Quantize.perChannel`). Expected laws, as for any
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
