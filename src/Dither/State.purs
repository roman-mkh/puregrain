module Dither.State where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Sequence (Seq)
import Dither.Fifo (class Fifo, replicate)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K
import Dither.Util (safeRange)

type RowLayer (f :: Type -> Type) a = Array (f a)

-- | Очередь "созревающих" RowLayer для одного конкретного dy. Стартует
-- | западдинной dy копиями пустого RowLayer ([]) — placeholder,
-- | естественно дающий нулевой вклад через sumErrors [] = 0.0, без
-- | какой-либо специальной обработки в Step.purs. Array, не Seq/List — 
-- | размер всегда мал (ограничен maxDepth ядра).

type DelayLine (f :: Type -> Type) a = Array (RowLayer f a)

-- | What crosses from one row to the next: the delay lines, and the index
-- | of the next row (`nextRow`, the `y` the quantizer will see). Keeping
-- | the row counter in the state, rather than passing `y` in, means a
-- | caller stepping row by row can't pass a wrong one.
type DitherState (f :: Type -> Type) a =
  { delayLines :: Array (DelayLine f a)
  , nextRow :: Int
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

freshLayer :: forall f a. Fifo f => Ring a => Array K.Offset -> RowLayer f a
freshLayer = map (\o -> replicate (K.paddingFor o) zero)

initState :: forall f a. CompiledKernel -> DitherState f a
initState compiled =
  { delayLines: map (\dy -> Array.replicate dy ([] :: RowLayer f a)) (safeRange 1 compiled.maxDepth)
  , nextRow: 0
  }