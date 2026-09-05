module Dither.State where

import Prelude

import Data.Array as Array
import Data.List.Lazy (List)
import Data.List.Lazy as LL
import Dither.Kernel (Kernel, Offset)
import Dither.Kernel as K

-- | Одна очередь ошибок, соответствующая одному конкретному offset'у (dx, dy).
-- | Ленивая, потенциально бесконечная (для начального "past" заполнена нулями).
type Fifo = List Number

-- | Набор FIFO-очередей для всех offset'ов внутри ОДНОГО конкретного dy
-- | (или, для current, всех offset'ов с dy == 0).
-- | Позиция в массиве соответствует позиции offset'а в отсортированном
-- | списке offset'ов этой категории (currentOffsets/futureOffsets по dy).
type RowLayer = Array Fifo

-- | Очередь слоёв, накопленных на M строк вперёд/назад.
-- | Индекс 0 — ближайшая строка (dy=1), индекс M-1 — самая дальняя (dy=M).
type RowQueue = Array RowLayer

type DitherState2 =
  { current :: RowLayer   -- offset'ы с dy == 0, живут и обнуляются в пределах одной строки
  , past    :: RowQueue   -- слои, уже созревшие и готовые к чтению (dy=1..M)
  , future  :: RowQueue   -- слои, куда пишем ошибки для будущих строк (dy=1..M)
  }

type DitherState =
  { current :: RowLayer
  , past    :: RowLayer
  , future  :: RowLayer
  }

initState :: Kernel -> DitherState
initState kernel =
  { current: freshLayer currentOs
  , past:    Array.replicate (Array.length futureOs) (LL.repeat 0.0)
  , future:  freshLayer futureOs
  }
  where
    currentOs = K.currentOffsets kernel
    futureOs  = K.futureOffsets kernel

advanceRow :: Kernel -> DitherState -> DitherState
advanceRow kernel state =
  { current: freshLayer currentOs
  , past:    Array.zipWith pastFor futureOs state.future
  , future:  freshLayer futureOs
  }
  where
    currentOs = K.currentOffsets kernel
    futureOs  = K.futureOffsets kernel

    pastFor :: Offset -> Fifo -> Fifo
    pastFor o fifo =
      let skip = K.skipFor o
      in LL.drop skip fifo <> LL.replicate skip 0.0    

freshLayer :: Array K.Offset -> RowLayer
freshLayer
 = map (\o -> LL.replicate (K.paddingFor o) 0.0)
-- freshLayer offsets = map (\o -> LL.replicate (K.paddingFor o) 0.0) offsets

-- | Строит свежую RowQueue — по одному пустому RowLayer (через freshLayer)
-- | на каждый dy-слой ядра. Используется для инициализации future
-- | и в initState, и в advanceRow (там всегда одинаково "с нуля").
-- freshRowQueue :: Kernel -> RowQueue
-- freshRowQueue kernel = map freshLayer (K.layeredFutureOffsets kernel)