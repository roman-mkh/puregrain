module Dither.Image where
 
import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
import Data.Tuple (Tuple(..))

import Dither.Kernel (Kernel)
import Dither.Row (ditherRow)
import Dither.State (DelayLine, initState)

ditherImage
  :: Kernel
  -> (Number -> Number)
  -> LL.List (Array Number)
  -> LL.List (Array Number)
ditherImage kernel quantize rows =
  go (initState kernel).delayLines rows
  where
    go :: Array DelayLine -> LL.List (Array Number) -> LL.List (Array Number)
    go delayLines remainingRows =
      case LL.step remainingRows of
        Nil -> LL.nil
        Cons row rest ->
          let
            Tuple delayLines' quantizedRow = ditherRow kernel quantize delayLines row
          in
            List (defer \_ -> Cons quantizedRow (go delayLines' rest))