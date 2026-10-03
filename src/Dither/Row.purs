module Dither.Row where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..), fst, snd)
import Dither.Fifo (class Fifo, replace)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K
import Dither.Pixel (class Scalable, Quantize)
import Dither.State (DelayLine, DitherState, RowLayer, RowState, freshLayer)
import Dither.Step (step)
import Partial.Unsafe (unsafeCrashWith)

extractMatured :: forall f a. Array (DelayLine f a) -> Tuple (Array (RowLayer f a)) (Array (DelayLine f a))
extractMatured delayLines =
  let fronts = map takeFront delayLines
  in Tuple (map fst fronts) (map snd fronts)
  where
    takeFront dl = case Array.uncons dl of
      Nothing -> unsafeCrashWith "Dither.Row.extractMatured: delayLine unexpectedly empty — padding invariant violated"
      Just { head, tail } -> Tuple head tail

initBuilding :: forall f a. Fifo f => Ring a => CompiledKernel -> Array (RowLayer f a)
initBuilding compiled = map freshLayer compiled.futureLayers

commitBuilding
  :: forall f a
   . Fifo f
  => Ring a
  => CompiledKernel
  -> Array (RowLayer f a)
  -> Array (DelayLine f a)
  -> Array (DelayLine f a)
commitBuilding compiled building shortenedDelayLines =
  Array.zipWith commitLayer compiled.futureLayers (Array.zip building shortenedDelayLines)
  where
    commitLayer offsets (Tuple layer dl) =
      Array.snoc dl (Array.zipWith adjustFifo offsets layer)

    adjustFifo o fifo = replace (K.skipFor o) fifo

-- | Dithers one row and returns the state for the next one. Use each
-- | `DitherState` once: passing an old state in again gives the right
-- | result, but can be slower (see `DitherState`).
ditherRow
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => CompiledKernel
  -> Quantize a
  -> DitherState f a
  -> Array a
  -> Tuple (DitherState f a) (Array a)
ditherRow compiled quantize state pixels =
  let
    Tuple matured0 shortenedDelayLines = extractMatured state.delayLines

    initial :: RowState f a
    initial =
      { current: freshLayer compiled.currentOffsets
      , matured: matured0
      , building: initBuilding compiled
      , x: 0
      , y: state.nextRow
      }

    result = mapAccumL stepAdapter initial pixels
    delayLines' = commitBuilding compiled result.accum.building shortenedDelayLines
  in
    Tuple { delayLines: delayLines', nextRow: state.nextRow + 1 } result.value
  where
    stepAdapter rowState px =
      let Tuple rowState' q = step compiled quantize rowState px
      in { accum: rowState', value: q }