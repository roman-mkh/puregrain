-- | One row of the diffusion: the step for each pixel, then handing the
-- | row's queues over to the rows below. Internal: may change without
-- | notice.
-- |
-- | A row runs left to right, or right to left under serpentine scanning
-- | (`Puregrain.Internal.Params.rightToLeft`). The queues hold their error
-- | fractions in the order of the row that produced them, so a queue for a
-- | row that runs the other way is reversed when it's handed over
-- | (`handOver`); with alternating rows, that's every queue for a row an
-- | odd number of rows below.
module Puregrain.Internal.Row
  ( stepRow
  , orStop
  , initBuilding
  , commitBuilding
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Traversable (mapAccumL, mapAccumR)
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Puregrain.Internal.Fifo (class Fifo, dequeue, replace, reverse)
import Puregrain.Internal.Kernel (CompiledKernel, paddingFor, skipFor)
import Puregrain.Internal.Params (CompiledParams, rightToLeft)
import Puregrain.Internal.Quantize (Quantizer)
import Puregrain.Internal.State (DelayLine, DitherState, RowLayer, RowState, freshLayer)
import Puregrain.Internal.Step (step)
import Puregrain.Kernel (Offset)
import Puregrain.Pixel (class Scalable)

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

-- | Hands a finished row's queues over to the rows below: each later
-- | row's layer joins the end of its delay line. `turns dy` says whether
-- | the row `dy` below runs the other way.
commitBuilding
  :: forall f a
   . Fifo f
  => Ring a
  => CompiledKernel
  -> (Int -> Boolean)
  -> Array (RowLayer f a)
  -> Array (DelayLine f a)
  -> Array (DelayLine f a)
commitBuilding compiled turns building shortenedDelayLines =
  Array.zipWith commitLayer (Array.mapWithIndex layerFor compiled.futureLayers) (Array.zip building shortenedDelayLines)
  where
    -- layer i holds the offsets of the row dy = i + 1 below
    layerFor i offsets = { offsets, turned: turns (i + 1) }

    commitLayer { offsets, turned } (Tuple layer dl) =
      Array.snoc dl (Array.zipWith (handOver turned) offsets layer)

-- | One finished queue, made ready for the row it's for, so that its
-- | entries come out in that row's scan order, one per column it visits.
-- |
-- | Built in the producing row's scan order, the queue holds `paddingFor o`
-- | zeros and then one entry per pixel; `replace (skipFor o)` shifts it so
-- | that entry k is the error for scan position k. For `dx > 0` that
-- | leaves `dx` entries past the row's end at the back, which a row
-- | running the same way never reads. For a row running the other way
-- | (`turned`), the queue is reversed, which brings those entries to the
-- | front, where they're dropped: then the entries come out last column
-- | first, one per column. (A row narrower than `-dx` gets `-dx` zeros,
-- | more than it reads, in either case: all its error went past the left
-- | edge, and `replace` drops everything.)
handOver :: forall f a. Fifo f => Ring a => Boolean -> Offset -> f a -> f a
handOver turned o fifo =
  let
    aligned = replace (skipFor o) fifo
  in
    if turned then dropFront (paddingFor o) (reverse aligned) else aligned

-- | Drops the first `n` entries. The queue always holds at least
-- | `paddingFor o` of them (the padding it started with, for a row of
-- | any width, even 0), so running out is a broken invariant.
dropFront :: forall f a. Fifo f => Int -> f a -> f a
dropFront n fifo
  | n <= 0 = fifo
  | otherwise = case dequeue fifo of
      Nothing -> unsafeCrashWith "Puregrain.Internal.Row.dropFront: FIFO exhausted - padding invariant violated"
      Just { tail } -> dropFront (n - 1) tail

-- | Dithers one row and returns the state for the next one. States are
-- | plain immutable values: stepping from an old one again (an undo, say)
-- | redoes that row's work, the queues' list reversals included, and no
-- | more.
-- |
-- | Every row must be as long as the first one. A row of a different
-- | length is a caller's bug: `Left` with a message naming the row,
-- | rather than reading past the queued error or leaving it misaligned
-- | for the rows below. The state isn't touched, so the caller can retry.
-- |
-- | The quantizer comes resolved (`Puregrain.Internal.Quantize.quantizerFor`),
-- | once per run by the caller, not once per row or pixel. The row's
-- | direction comes from the scan and the row's index, `state.nextRow`.
stepRow
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => CompiledParams
  -> Quantizer a
  -> DitherState f a
  -> Array a
  -> Either String (Tuple (DitherState f a) (Array a))
stepRow compiled quantizer state pixels =
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
        y = state.nextRow
        backwards = rightToLeft compiled.scan y
        Tuple matured0 shortenedDelayLines = extractMatured state.delayLines

        -- On a row scanned right to left, x starts at the right edge and
        -- counts down, so the quantizer still gets each pixel's column.
        initial :: RowState f a
        initial =
          { current: freshLayer compiled.kernel.currentOffsets
          , matured: matured0
          , building: initBuilding compiled.kernel
          , x: if backwards then length - 1 else 0
          , xStep: if backwards then -1 else 1
          , y
          }

        -- `mapAccumR` visits the pixels from the last one; both give the
        -- results back in the row's own order, left to right.
        result =
          if backwards then mapAccumR stepAdapter initial pixels
          else mapAccumL stepAdapter initial pixels
        turns dy = rightToLeft compiled.scan (y + dy) /= backwards
        delayLines' = commitBuilding compiled.kernel turns result.accum.building shortenedDelayLines
      in
        Right (Tuple { delayLines: delayLines', nextRow: state.nextRow + 1, width: Just length } result.value)
  where
    length = Array.length pixels

    stepAdapter rowState px =
      let Tuple rowState' q = step compiled.kernel quantizer rowState px
      in { accum: rowState', value: q }

-- | The other half of `stepRow`'s contract: its `Left` (a row of a
-- | different length, a caller's bug) becomes a stop with the same
-- | message. For the drivers whose result type can't carry an error:
-- | `ditherImage` and `ditherRows` (`Puregrain.Internal.Image`), and
-- | `ditherCells` and `ditherBands` (`Puregrain.Cells`).
orStop :: forall a. Either String a -> a
orStop = case _ of
  Left problem -> unsafeCrashWith problem
  Right a -> a
