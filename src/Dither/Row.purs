module Dither.Row where

import Prelude

import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..))

import Dither.Kernel (Kernel)
import Dither.State (DitherState)
import Dither.Step (step)

ditherRow
  :: Kernel
  -> (Number -> Number)
  -> DitherState
  -> Array Number
  -> Tuple DitherState (Array Number)
ditherRow kernel quantize state0 pixels =
  let result = mapAccumL stepAdapter state0 pixels
  in Tuple result.accum result.value
  where
    stepAdapter :: DitherState -> Number -> { accum :: DitherState, value :: Number }
    stepAdapter s px =
      let Tuple s' q = step kernel quantize s px
      in { accum: s', value: q }