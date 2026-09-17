module Dither.Step where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)

import Dither.Fifo (class Fifo, dequeue, enqueue)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K
import Dither.State (RowLayer, RowState)

dequeueOne :: forall f. Fifo f => f -> Tuple Number f
dequeueOne fifo = case dequeue fifo of
  Nothing -> unsafeCrashWith "Dither.Step.dequeueOne: FIFO exhausted — padding/kernel invariant violated"
  Just { head, tail } -> Tuple head tail

dequeueAllLayer :: forall f. Fifo f => RowLayer f -> Tuple (Array Number) (RowLayer f)
dequeueAllLayer fifos = Tuple (map fst results) (map snd results)
  where
    results = map dequeueOne fifos

sumErrors :: Array Number -> Number
sumErrors = Array.foldl (+) 0.0

enqueueWeighted :: forall f. Fifo f => Number -> K.Offset -> f -> f
enqueueWeighted err offset fifo = enqueue fifo (err * offset.weight)

step
  :: forall f
   . Fifo f
  => CompiledKernel
  -> (Number -> Number)
  -> RowState f
  -> Number
  -> Tuple (RowState f) Number
step compiled quantize { current, matured, building } pixel =
  let
    Tuple currentErrs current' = dequeueAllLayer current

    maturedResults = map dequeueAllLayer matured
    maturedErrs = map fst maturedResults
    matured' = map snd maturedResults

    incomingError =
      sumErrors currentErrs
        + Array.foldl (\acc errs -> acc + sumErrors errs) 0.0 maturedErrs

    corrected = pixel + incomingError
    quantized = quantize corrected
    outErr    = corrected - quantized

    current'' = Array.zipWith (enqueueWeighted outErr) compiled.currentOffsets current'

    building' = Array.zipWith enqueueLayer compiled.futureLayers building
      where
        enqueueLayer offsets layer = Array.zipWith (enqueueWeighted outErr) offsets layer
  in
    Tuple { current: current'', matured: matured', building: building' } quantized