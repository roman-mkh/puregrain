module Dither.Row where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)

import Dither.Fifo (class Fifo, replace)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K
import Dither.State (DelayLine, RowLayer, RowState, freshLayer)
import Dither.Step (step)

extractMatured :: forall f. Array (DelayLine f) -> Tuple (Array (RowLayer f)) (Array (DelayLine f))
extractMatured delayLines =
  let fronts = map takeFront delayLines
  in Tuple (map fst fronts) (map snd fronts)
  where
    takeFront :: DelayLine f -> Tuple (RowLayer f) (DelayLine f)
    takeFront dl = case Array.uncons dl of
      Nothing -> unsafeCrashWith "Dither.Row.extractMatured: delayLine unexpectedly empty — padding invariant violated"
      Just { head, tail } -> Tuple head tail

initBuilding :: forall f. Fifo f => CompiledKernel -> Array (RowLayer f)
initBuilding compiled = map freshLayer compiled.futureLayers

commitBuilding
  :: forall f
   . Fifo f
  => CompiledKernel
  -> Array (RowLayer f)
  -> Array (DelayLine f)
  -> Array (DelayLine f)
commitBuilding compiled building shortenedDelayLines =
  Array.zipWith commitLayer compiled.futureLayers (Array.zip building shortenedDelayLines)
  where
    commitLayer :: Array K.Offset -> Tuple (RowLayer f) (DelayLine f) -> DelayLine f
    commitLayer offsets (Tuple layer dl) =
      Array.snoc dl (Array.zipWith adjustFifo offsets layer)

    adjustFifo :: K.Offset -> f -> f
    adjustFifo o fifo = replace (K.skipFor o) fifo

ditherRow
  :: forall f
   . Fifo f
  => CompiledKernel
  -> (Number -> Number)
  -> Array (DelayLine f)
  -> Array Number
  -> Tuple (Array (DelayLine f)) (Array Number)
ditherRow compiled quantize delayLines0 pixels =
  let
    Tuple matured0 shortenedDelayLines = extractMatured delayLines0

    initial :: RowState f
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
    stepAdapter :: RowState f -> Number -> { accum :: RowState f, value :: Number }
    stepAdapter rowState px =
      let Tuple rowState' q = step compiled quantize rowState px
      in { accum: rowState', value: q }