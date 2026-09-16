module Dither.State where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.List.Lazy (List)
import Data.List.Lazy as LL

import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K

type Fifo = List Number
type RowLayer = Array Fifo

-- | Очередь "созревающих" RowLayer для одного конкретного dy. Стартует
-- | западдинной dy копиями пустого RowLayer ([]) — placeholder,
-- | естественно дающий нулевой вклад через sumErrors [] = 0.0, без
-- | какой-либо специальной обработки в Step.purs. Array, не Seq/List —
-- | размер всегда мал (ограничен maxDepth ядра).
type DelayLine = Array RowLayer

type DitherState = { delayLines :: Array DelayLine }

type RowState =
  { current  :: RowLayer
  , matured  :: Array RowLayer
  , building :: Array RowLayer
  }

freshLayer :: Array K.Offset -> RowLayer
freshLayer = map (\o -> LL.replicate (K.paddingFor o) 0.0)

-- | Каждый DelayLine стартует западдинным dy копиями пустого RowLayer —
-- | для dy=1 это 1 placeholder, для dy=2 — 2, и т.д.
initState :: CompiledKernel -> DitherState
initState compiled =
  { delayLines: map (\dy -> Array.replicate dy ([] :: RowLayer)) (1 .. compiled.maxDepth) }