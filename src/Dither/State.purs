module Dither.State where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.List.Lazy (List)
import Data.List.Lazy as LL
import Data.Tuple (Tuple)
import Dither.Kernel (Kernel)
import Dither.Kernel as K

-- | Одна очередь ошибок, соответствующая одному конкретному offset'у (dx, dy).
-- | Ленивая, потенциально бесконечная (для начального заполнения delayLines).
type Fifo = List Number

-- | Набор FIFO-очередей для всех offset'ов внутри одного конкретного dy
-- | (или, для current, всех offset'ов с dy == 0).
type RowLayer = Array Fifo

-- | Очередь "созревающих" RowLayer для одного конкретного dy.
-- | Инвариант: длина всегда равна dy — на каждом пикселе снимается
-- | голова (matured, готова к чтению) и дописывается новый хвост
-- | (только что построенный из ошибки текущего пикселя).
type DelayLine = List RowLayer

-- | Состояние, переживающее границы строк — M штук DelayLine, индекс i
-- | соответствует dy = i + 1. current (dy=0 offset'ы) сюда НЕ входит —
-- | он живёт и пересоздаётся в пределах одной строки (см. Dither.Row).
type DitherState = { delayLines :: Array DelayLine }

-- | Состояние, живущее внутри одной строки: current (dy=0, сбрасывается
-- | на каждой строке) и delayLines (dy>0, переживает границы строк,
-- | эволюционирует попиксельно внутри step).
type RowState = Tuple RowLayer (Array DelayLine)

-- | Строит свежий RowLayer — по одному пустому (с паддингом по dx) Fifo
-- | на каждый переданный offset. Используется для current в начале
-- | каждой строки.
freshLayer :: Array K.Offset -> RowLayer
freshLayer = map (\o -> LL.replicate (K.paddingFor o) 0.0)

-- | Бесконечно-нулевой RowLayer под конкретный набор offset'ов —
-- | используется для заполнения DelayLine перед первой строкой картинки.
infiniteZeroLayer :: Array K.Offset -> RowLayer
infiniteZeroLayer offsets = map (const (LL.repeat 0.0)) offsets

-- | Начальное состояние delayLines перед первой строкой картинки:
-- | для dy = i+1, DelayLine содержит ровно (i+1) копий бесконечно-нулевого
-- | RowLayer — ни одна строка ещё не обработана, все "прошлые" вклады
-- | считаются нулевыми на всю глубину dy.
initState :: Kernel -> DitherState
initState kernel =
  { delayLines: map initDelayLineFor (1 .. depth) }
  where
    depth :: Int
    depth = K.maxDepth kernel

    initDelayLineFor :: Int -> DelayLine
    initDelayLineFor dy =
      let offsets = K.offsetsForDy kernel dy
      in LL.fromFoldable (Array.replicate dy (infiniteZeroLayer offsets))