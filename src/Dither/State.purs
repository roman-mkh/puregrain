module Dither.State where

import Prelude

import Data.Array ((..))
import Data.Array as Array

import Dither.Fifo (class Fifo, replicate)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K

type RowLayer f = Array f

-- | Очередь "созревающих" RowLayer для одного конкретного dy. Стартует
-- | западдинной dy копиями пустого RowLayer ([]) — placeholder,
-- | естественно дающий нулевой вклад через sumErrors [] = 0.0, без
-- | какой-либо специальной обработки в Step.purs. Array, не Seq/List —
-- | размер всегда мал (ограничен maxDepth ядра).

type DelayLine f = Array (RowLayer f)

type DitherState f = { delayLines :: Array (DelayLine f) }

type RowState f =
  { current  :: RowLayer f
  , matured  :: Array (RowLayer f)
  , building :: Array (RowLayer f)
  }

freshLayer :: forall f. Fifo f => Array K.Offset -> RowLayer f
freshLayer = map (\o -> replicate (K.paddingFor o) 0.0)

-- | Doesn't need `Fifo f =>` — `[]` needs no class method at all.
initState :: forall f. CompiledKernel -> DitherState f
initState compiled =
  { delayLines: map (\dy -> Array.replicate dy ([] :: RowLayer f)) (1 .. compiled.maxDepth) }