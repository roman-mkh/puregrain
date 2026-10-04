-- | The state the diffusion carries along: the queues of error fractions
-- | waiting for later pixels. Internal: may change without notice.
module Puregrain.Internal.State
  ( RowLayer
  , DelayLine
  , DitherState
  , RowState
  , freshLayer
  , initState
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Puregrain.Internal.Fifo (class Fifo, replicate)
import Puregrain.Internal.Kernel (CompiledKernel, paddingFor)
import Puregrain.Internal.Util (safeRange)
import Puregrain.Kernel (Offset)

-- | One queue per kernel offset of one row: the error fractions on their
-- | way to the pixels of a later row (or, for the current row's offsets,
-- | to pixels further right).
type RowLayer (f :: Type -> Type) a = Array (f a)

-- | The maturing `RowLayer`s for one `dy`. It starts padded with `dy`
-- | copies of the empty `RowLayer` (`[]`): a placeholder that contributes
-- | zero error for free (`sumErrors [] = zero`), with no special case in
-- | the step. An `Array` rather than a queue: it's always short, at most
-- | the kernel's `maxDepth`.
type DelayLine (f :: Type -> Type) a = Array (RowLayer f a)

-- | What crosses from one row to the next: the delay lines; the index of
-- | the next row (`nextRow`, the `y` the quantizer will see), kept here
-- | rather than passed in, so a caller stepping row by row can't pass a
-- | wrong one; and the image's `width`, taken from the first row
-- | (`Nothing` before it), which every later row must match.
-- |
-- | Use each `DitherState` once. Passing an old state in again gives the
-- | right result, but can be slower: the queues inside it then repeat
-- | work they already did (see the `CatQueue` instance in `Puregrain.Internal.Fifo`).
type DitherState (f :: Type -> Type) a =
  { delayLines :: Array (DelayLine f a)
  , nextRow :: Int
  , width :: Maybe Int
  }

-- | Row-local state, rebuilt for every pixel. `x` is the column of the
-- | next pixel and `y` this row's index — carried here rather than
-- | computed by an indexed traversal, because `step` rebuilds this record
-- | per pixel anyway (no extra allocation), whereas `mapAccumLWithIndex`
-- | on Array is a generic default with an extra pass per row.
type RowState (f :: Type -> Type) a =
  { current  :: RowLayer f a
  , matured  :: Array (RowLayer f a)
  , building :: Array (RowLayer f a)
  , x :: Int
  , y :: Int
  }

freshLayer :: forall f a. Fifo f => Ring a => Array Offset -> RowLayer f a
freshLayer = map (\o -> replicate (paddingFor o) zero)

initState :: forall f a. CompiledKernel -> DitherState f a
initState compiled =
  { delayLines: map (\dy -> Array.replicate dy ([] :: RowLayer f a)) (safeRange 1 compiled.maxDepth)
  , nextRow: 0
  , width: Nothing
  }