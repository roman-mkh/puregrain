module Dither.Step where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Dither.Kernel (Kernel, Offset)
import Dither.Kernel as K
import Dither.State (DitherState, Fifo)
import Partial.Unsafe (unsafeCrashWith)

dequeueOne :: Fifo -> Tuple Number Fifo
dequeueOne fifo = case LL.uncons fifo of
  Nothing -> unsafeCrashWith "Dither.Step.dequeueOne: FIFO exhausted — padding/kernel invariant violated"
  Just { head, tail } -> Tuple head tail

dequeueAll :: Array Fifo -> Tuple (Array Number) (Array Fifo)
dequeueAll fifos = Tuple (map fst results) (map snd results)
  where results = map dequeueOne fifos

sumErrors :: Array Number -> Number
sumErrors = Array.foldl (+) 0.0

step
  :: Kernel
  -> (Number -> Number)
  -> DitherState
  -> Number
  -> Tuple DitherState Number
step kernel quantize state pixel =
  let
    -- Шаг 1: собрать входящую ошибку
    Tuple currentErrs current' = dequeueAll state.current
    Tuple pastErrs    past'    = dequeueAll state.past
    incomingError = sumErrors currentErrs + sumErrors pastErrs

    -- Шаг 2: скорректировать, квантовать
    corrected = pixel + incomingError
    quantized = quantize corrected
    outErr    = corrected - quantized

    -- Шаг 3: распределить outErr по весам, записать
    current'' = Array.zipWith (enqueueWeighted outErr) (K.currentOffsets kernel) current'
    future'   = Array.zipWith (enqueueWeighted outErr) (K.futureOffsets kernel) state.future

    newState = { current: current'', past: past', future: future' }
  in
    Tuple newState quantized
  where
    enqueueWeighted :: Number -> Offset -> Fifo -> Fifo
    enqueueWeighted err offset fifo = LL.snoc fifo (err * offset.weight)