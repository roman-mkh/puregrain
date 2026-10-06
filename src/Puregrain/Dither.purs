-- | Dithering a whole image: `ditherImage` for an image in memory,
-- | `ditherRows` for a lazy stream of rows. Both run error diffusion with a
-- | kernel (`Puregrain.Kernel`) and a quantizer (`Puregrain.Quantize`,
-- | `Puregrain.Palette`, `Puregrain.Ordered`), and give the same rows for
-- | the same input.
module Puregrain.Dither
  ( ditherImage
  , ditherRows
  ) where

import Prelude

import Data.CatQueue (CatQueue)
import Data.List.Lazy as LL
import Puregrain.Internal.Image (ditherImageWith, ditherRowsWith)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class Scalable)
import Puregrain.Quantize (Quantize)
import Type.Proxy (Proxy(..))

-- | Dithers an image in memory: an array of rows, top to bottom, each an
-- | array of pixels from left to right. Returns the dithered image the
-- | same way, all at once.
-- |
-- | All rows must have the same length. A row of a different length is a
-- | bug in the caller: `ditherImage` stops with an error naming it.
-- |
-- | `kernel` says where each pixel's quantization error goes;
-- | `noDiffusion` passes none on. `quantize` picks each output value.
ditherImage
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
ditherImage = ditherImageWith (Proxy :: Proxy CatQueue)

-- | Dithers a stream of rows: a lazy list of rows in, a lazy list of
-- | dithered rows out. Each row is read and dithered only when its result
-- | is first needed, so only the rows in flight are in memory, and the
-- | input may even be endless. Gives the same rows as `ditherImage`.
-- |
-- | All rows must have the same length. A row of a different length is a
-- | bug in the caller: when that row is reached, `ditherRows` stops with an
-- | error naming it (the rows before it have come out already).
ditherRows
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherRows = ditherRowsWith (Proxy :: Proxy CatQueue)
