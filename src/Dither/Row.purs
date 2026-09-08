module Dither.Row where

import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..))

import Dither.Kernel (Kernel)
import Dither.Kernel as K
import Dither.State (DelayLine, RowState, freshLayer)
import Dither.Step (step)

ditherRow
  :: Kernel
  -> (Number -> Number)
  -> Array DelayLine
  -> Array Number
  -> Tuple (Array DelayLine) (Array Number)
ditherRow kernel quantize delayLines0 pixels =
  let
    initial :: RowState
    initial = Tuple (freshLayer (K.currentOffsets kernel)) delayLines0

    result = mapAccumL stepAdapter initial pixels

    Tuple _finalCurrent finalDelayLines = result.accum
  in
    Tuple finalDelayLines result.value
  where
    stepAdapter :: RowState -> Number -> { accum :: RowState, value :: Number }
    stepAdapter rowState px =
      let Tuple rowState' q = step kernel quantize rowState px
      in { accum: rowState', value: q }