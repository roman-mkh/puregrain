module Dither.State where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Sequence (Seq)

import Dither.Fifo (class Fifo, replicate)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K

type RowLayer (f :: Type -> Type) a = Array (f a)

-- | Очередь "созревающих" RowLayer для одного конкретного dy. Стартует
-- | западдинной dy копиями пустого RowLayer ([]) — placeholder,
-- | естественно дающий нулевой вклад через sumErrors [] = 0.0, без
-- | какой-либо специальной обработки в Step.purs. Array, не Seq/List — 
-- | размер всегда мал (ограничен maxDepth ядра).

type DelayLine (f :: Type -> Type) a = Array (RowLayer f a)

type DitherState (f :: Type -> Type) a = { delayLines :: Array (DelayLine f a) }

type RowState (f :: Type -> Type) a =
  { current  :: RowLayer f a
  , matured  :: Array (RowLayer f a)
  , building :: Array (RowLayer f a)
  }

freshLayer :: forall f a. Fifo f => Ring a => Array K.Offset -> RowLayer f a
freshLayer = map (\o -> replicate (K.paddingFor o) zero)

initState :: forall f a. CompiledKernel -> DitherState f a
initState compiled =
  { delayLines: map (\dy -> Array.replicate dy ([] :: RowLayer f a)) (1 .. compiled.maxDepth) }