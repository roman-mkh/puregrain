-- | Dithering a whole image: `ditherImage` runs error diffusion over the
-- | image row by row, with a kernel (`Puregrain.Kernel`) and a quantizer
-- | (`Puregrain.Quantize`, `Puregrain.Palette`, `Puregrain.Ordered`).
module Puregrain.Dither
  ( ditherImage
  ) where

import Prelude

import Data.CatQueue (CatQueue)
import Data.List.Lazy as LL
import Puregrain.Internal.Image (ditherImageWith)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class Scalable)
import Puregrain.Quantize (Quantize)
import Type.Proxy (Proxy(..))

-- | Dithers an image given as a lazy list of rows, top to bottom, each an
-- | array of pixels from left to right. The result comes back the same
-- | way, and lazily: each row is read and dithered when its result is
-- | first needed, so an image can be processed as a stream.
-- |
-- | All rows must have the same length. A row of a different length is
-- | a bug in the caller: when that row is reached, `ditherImage` stops
-- | with an error naming it (the rows before it have come out already).
-- |
-- | `kernel` says where each pixel's quantization error goes;
-- | `noDiffusion` passes none on. `quantize` picks each output value.
ditherImage
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherImage = ditherImageWith (Proxy :: Proxy CatQueue)
