module Dither.Image where

import Prelude

import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
import Data.Sequence (Seq)
import Data.Tuple (Tuple(..))
import Dither.Fifo (class Fifo)
import Dither.Kernel (Kernel, compileKernel)
import Dither.Pixel (class Scalable, Quantize)
import Dither.Row (ditherRow)
import Dither.State (DelayLine, initState)
import Type.Proxy (Proxy(..))

ditherImageWith
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => Proxy f
  -> Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherImageWith _ kernel quantize rows =
  go (initState compiled).delayLines rows
  where
    compiled = compileKernel kernel

    go :: Array (DelayLine f a) -> LL.List (Array a) -> LL.List (Array a)
    go delayLines remainingRows =
      case LL.step remainingRows of
        Nil -> LL.nil
        Cons row rest ->
          let Tuple delayLines' quantizedRow = ditherRow compiled quantize delayLines row
          in List (defer \_ -> Cons quantizedRow (go delayLines' rest))

ditherImage
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherImage = ditherImageWith (Proxy :: Proxy Seq)