-- | Runs the diffusion over a lazy list of rows, with any `Fifo` backend.
-- | Internal: `Puregrain.Dither.ditherImage` is this with the production
-- | backend; the tests use it to check every backend against a reference.
module Puregrain.Internal.Image
  ( ditherImageWith
  ) where

import Prelude

import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
import Data.Tuple (Tuple(..))
import Puregrain.Internal.Fifo (class Fifo)
import Puregrain.Internal.Kernel (compileKernel)
import Puregrain.Internal.Row (ditherRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class Scalable)
import Puregrain.Quantize (Quantize)
import Type.Proxy (Proxy)

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
  go (initState compiled) rows
  where
    compiled = compileKernel kernel

    -- All the work happens inside `defer`: a row is read and dithered only
    -- when its cell is forced. (With the `let` outside it, as before, a
    -- strict `let` dithered each row one cell early.)
    go :: DitherState f a -> LL.List (Array a) -> LL.List (Array a)
    go state remainingRows = List $ defer \_ ->
      case LL.step remainingRows of
        Nil -> Nil
        Cons row rest ->
          let Tuple state' quantizedRow = ditherRow compiled quantize state row
          in Cons quantizedRow (go state' rest)
