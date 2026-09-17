module Dither.Image where

import Prelude

import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
-- import Data.Sequence (Seq)
import Data.Tuple (Tuple(..))
import Type.Proxy (Proxy(..))

import Dither.Fifo (class Fifo)
import Dither.Kernel (CompiledKernel, Kernel, compileKernel)
import Dither.Row (ditherRow)
import Dither.State (DelayLine, initState)

-- | Generic, backend-polymorphic core — used directly by benchmarks and
-- | tests that need to pick a specific `Fifo` instance to measure. The
-- | `Proxy f` argument exists solely so the caller can pin `f`; it
-- | carries no runtime information.
ditherImageWith
  :: forall f
   . Fifo f
  => Proxy f
  -> Kernel
  -> (Number -> Number)
  -> LL.List (Array Number)
  -> LL.List (Array Number)
ditherImageWith _ kernel quantize rows =
  go (initState compiled).delayLines rows
  where
    compiled :: CompiledKernel
    compiled = compileKernel kernel

    go :: Array (DelayLine f) -> LL.List (Array Number) -> LL.List (Array Number)
    go delayLines remainingRows =
      case LL.step remainingRows of
        Nil -> LL.nil
        Cons row rest ->
          let
            Tuple delayLines' quantizedRow = ditherRow compiled quantize delayLines row
          in
            List (defer \_ -> Cons quantizedRow (go delayLines' rest))

-- | Public entry point. Dithers an image using the library's chosen
-- | default `Fifo` backend (`Seq Number`). Callers never need to know
-- | `class Fifo` exists.
ditherImage
  :: Kernel
  -> (Number -> Number)
  -> LL.List (Array Number)
  -> LL.List (Array Number)
--ditherImage = ditherImageWith (Proxy :: Proxy (Seq Number))
ditherImage = ditherImageWith (Proxy :: Proxy (LL.List Number))