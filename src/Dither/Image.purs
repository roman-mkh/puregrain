module Dither.Image where

import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
import Data.Tuple (Tuple(..))

import Dither.Kernel (Kernel)
import Dither.Row (ditherRow)
import Dither.State (DitherState, initState, advanceRow)

ditherImage
  :: Kernel
  -> (Number -> Number)
  -> LL.List (Array Number)
  -> LL.List (Array Number)
ditherImage kernel quantize rows =
  go (initState kernel) rows
  where
    go :: DitherState -> LL.List (Array Number) -> LL.List (Array Number)
    go state remainingRows =
      case LL.step remainingRows of
        Nil -> LL.nil
        Cons row rest ->
          let
            Tuple state' quantizedRow = ditherRow kernel quantize state row
            state'' = advanceRow kernel state'
          in
            List (defer \_ -> Cons quantizedRow (go state'' rest))