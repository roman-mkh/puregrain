module Dither.Row where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..), fst, snd)
import Dither.Kernel (Kernel)
import Dither.Kernel as K
import Dither.State (DelayLine, Fifo, RowLayer, RowState, freshLayer)
import Dither.Step (step)
import Partial.Unsafe (unsafeCrashWith)

-- | Извлекает "созревший" front из каждого DelayLine — M RowLayer, готовых
-- | к чтению для этой строки — и возвращает их вместе с укороченными
-- | (ещё не дополненными новым хвостом) delayLines.
extractMatured :: Array DelayLine -> Tuple (Array RowLayer) (Array DelayLine)
extractMatured delayLines =
  let fronts = map takeFront delayLines
  in Tuple (map fst fronts) (map snd fronts)
  where
    takeFront :: DelayLine -> Tuple RowLayer DelayLine
    takeFront dl = case LL.uncons dl of
      Nothing -> unsafeCrashWith "Dither.Row.extractMatured: delayLine unexpectedly empty"
      Just { head, tail } -> Tuple head tail

-- | Строит M свежих (с паддингом по dx для положительных dx) RowLayer —
-- | начальное состояние building перед обработкой строки.
initBuilding :: Kernel -> Array RowLayer
initBuilding kernel = map freshLayer (K.layeredFutureOffsets kernel)

-- | Дописывает полностью накопленный (после всей строки) building в
-- | укороченные delayLines — по одному новому хвосту на каждый dy-слой,
-- | с компенсирующим skip для отрицательных dx.
commitBuilding :: Kernel -> Array RowLayer -> Array DelayLine -> Array DelayLine
commitBuilding kernel building shortenedDelayLines =
  Array.zipWith commitLayer layers (Array.zip building shortenedDelayLines)
  where
    layers :: Array (Array K.Offset)
    layers = K.layeredFutureOffsets kernel

    commitLayer :: Array K.Offset -> Tuple RowLayer DelayLine -> DelayLine
    commitLayer offsets (Tuple layer dl) =
      LL.snoc dl (Array.zipWith adjustFifo offsets layer)

    adjustFifo :: K.Offset -> Fifo -> Fifo
    adjustFifo o fifo =
      let skip = K.skipFor o
      in LL.drop skip fifo <> LL.replicate skip 0.0

ditherRow
  :: Kernel
  -> (Number -> Number)
  -> Array DelayLine
  -> Array Number
  -> Tuple (Array DelayLine) (Array Number)
ditherRow kernel quantize delayLines0 pixels =
  let
    Tuple matured0 shortenedDelayLines = extractMatured delayLines0

    initial :: RowState
    initial =
      { current: freshLayer (K.currentOffsets kernel)
      , matured: matured0
      , building: initBuilding kernel
      }

    result = mapAccumL stepAdapter initial pixels

    finalBuilding = result.accum.building

    delayLines' = commitBuilding kernel finalBuilding shortenedDelayLines
  in
    Tuple delayLines' result.value
  where
    stepAdapter :: RowState -> Number -> { accum :: RowState, value :: Number }
    stepAdapter rowState px =
      let Tuple rowState' q = step kernel quantize rowState px
      in { accum: rowState', value: q }