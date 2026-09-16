module Dither.Row where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..), fst, snd)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K
import Dither.State (DelayLine, Fifo, RowLayer, RowState, freshLayer)
import Dither.Step (step)
import Partial.Unsafe (unsafeCrashWith)

extractMatured :: Array DelayLine -> Tuple (Array RowLayer) (Array DelayLine)
extractMatured delayLines =
  let fronts = map takeFront delayLines
  in Tuple (map fst fronts) (map snd fronts)
  where
    takeFront :: DelayLine -> Tuple RowLayer DelayLine
    takeFront dl = case Array.uncons dl of
      Nothing -> unsafeCrashWith "Dither.Row.extractMatured: delayLine unexpectedly empty — padding invariant violated"
      Just { head, tail } -> Tuple head tail

initBuilding :: CompiledKernel -> Array RowLayer
initBuilding compiled = map freshLayer compiled.futureLayers

commitBuilding :: CompiledKernel -> Array RowLayer -> Array DelayLine -> Array DelayLine
commitBuilding compiled building shortenedDelayLines =
  Array.zipWith commitLayer compiled.futureLayers (Array.zip building shortenedDelayLines)
  where
    commitLayer :: Array K.Offset -> Tuple RowLayer DelayLine -> DelayLine
    commitLayer offsets (Tuple layer dl) =
      Array.snoc dl (Array.zipWith adjustFifo offsets layer)

    adjustFifo :: K.Offset -> Fifo -> Fifo
    adjustFifo o fifo =
      let skip = K.skipFor o
      in LL.drop skip fifo <> LL.replicate skip 0.0

ditherRow
  :: CompiledKernel
  -> (Number -> Number)
  -> Array DelayLine
  -> Array Number
  -> Tuple (Array DelayLine) (Array Number)
ditherRow compiled quantize delayLines0 pixels =
  let
    Tuple matured0 shortenedDelayLines = extractMatured delayLines0

    initial :: RowState
    initial =
      { current: freshLayer compiled.currentOffsets
      , matured: matured0
      , building: initBuilding compiled
      }

    result = mapAccumL stepAdapter initial pixels
    delayLines' = commitBuilding compiled result.accum.building shortenedDelayLines
  in
    Tuple delayLines' result.value
  where
    stepAdapter :: RowState -> Number -> { accum :: RowState, value :: Number }
    stepAdapter rowState px =
      let Tuple rowState' q = step compiled quantize rowState px
      in { accum: rowState', value: q }