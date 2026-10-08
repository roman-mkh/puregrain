-- | One row of the diffusion: the step for each pixel, then handing the
-- | row's queues over to the rows below. Internal: may change without
-- | notice.
module Puregrain.Internal.Row
  ( stepRow
  , initBuilding
  , commitBuilding
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Puregrain.Internal.Fifo (class Fifo, replace)
import Puregrain.Internal.Kernel (CompiledKernel, skipFor)
import Puregrain.Internal.State (DelayLine, DitherState, RowLayer, RowState, freshLayer)
import Puregrain.Internal.Step (step)
import Puregrain.Pixel (class Scalable)
import Puregrain.Quantize (Quantize)

extractMatured :: forall f a. Array (DelayLine f a) -> Tuple (Array (RowLayer f a)) (Array (DelayLine f a))
extractMatured delayLines =
  let fronts = map takeFront delayLines
  in Tuple (map fst fronts) (map snd fronts)
  where
    takeFront dl = case Array.uncons dl of
      Nothing -> unsafeCrashWith "Puregrain.Internal.Row.extractMatured: delayLine unexpectedly empty - padding invariant violated"
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

    adjustFifo o fifo = replace (skipFor o) fifo

-- | Dithers one row and returns the state for the next one. States are
-- | plain immutable values: stepping from an old one again (an undo, say)
-- | redoes that row's work, the queues' list reversals included, and no
-- | more.
-- |
-- | Every row must be as long as the first one. A row of a different
-- | length is a caller's bug: `Left` with a message naming the row,
-- | rather than reading past the queued error or leaving it misaligned
-- | for the rows below. The state isn't touched, so the caller can retry.
stepRow
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => CompiledKernel
  -> Quantize a
  -> DitherState f a
  -> Array a
  -> Either String (Tuple (DitherState f a) (Array a))
stepRow compiled quantize state pixels =
  -- The check comes first, and the row's work lives in the branch after
  -- it: PureScript evaluates `where` bindings before the body, so work
  -- placed there would run (and, for a longer row, crash) before the check.
  case state.width of
    Just width | width /= length ->
      Left
        ( "puregrain: row " <> show state.nextRow <> " has " <> show length
            <> " pixels, but the first row has " <> show width
            <> "; all rows of an image must have the same length"
        )
    _ ->
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
        Right (Tuple { delayLines: delayLines', nextRow: state.nextRow + 1, width: Just length } result.value)
  where
    length = Array.length pixels

    stepAdapter rowState px =
      let Tuple rowState' q = step compiled quantize rowState px
      in { accum: rowState', value: q }
