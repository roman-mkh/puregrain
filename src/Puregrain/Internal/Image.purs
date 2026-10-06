-- | The two drivers that run the diffusion over a whole image, row by row,
-- | with any `Fifo` backend: `ditherImageWith` over an array of rows (all at
-- | once) and `ditherRowsWith` over a lazy list of rows (each when asked
-- | for). Both drive the same `ditherRow`, so they give the same result.
-- | Internal: `Puregrain.Dither` exports them with the production backend;
-- | the tests use them to check every backend against a reference.
module Puregrain.Internal.Image
  ( ditherImageWith
  , ditherRowsWith
  ) where

import Prelude

import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..))
import Puregrain.Internal.Fifo (class Fifo)
import Puregrain.Internal.Kernel (compileKernel)
import Puregrain.Internal.Row (ditherRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class Scalable)
import Puregrain.Quantize (Quantize)
import Type.Proxy (Proxy)

-- | An image in memory: a strict fold over the array of rows.
ditherImageWith
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => Proxy f
  -> Kernel
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
ditherImageWith _ kernel quantize rows =
  (mapAccumL next (initState compiled :: DitherState f a) rows).value
  where
    compiled = compileKernel kernel

    next state row =
      let Tuple state' quantizedRow = ditherRow compiled quantize state row
      in { accum: state', value: quantizedRow }

-- | A stream of rows: a lazy unfold over the list of rows.
ditherRowsWith
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => Proxy f
  -> Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherRowsWith _ kernel quantize rows =
  go (initState compiled) rows
  where
    compiled = compileKernel kernel

    -- All the work happens inside `defer`: a row is read and dithered only
    -- when its cell is forced. (With the `let` outside it, as before
    -- 2026-10-04, a strict `let` dithered each row one cell early.)
    go :: DitherState f a -> LL.List (Array a) -> LL.List (Array a)
    go state remainingRows = List $ defer \_ ->
      case LL.step remainingRows of
        Nil -> Nil
        Cons row rest ->
          let Tuple state' quantizedRow = ditherRow compiled quantize state row
          in Cons quantizedRow (go state' rest)
