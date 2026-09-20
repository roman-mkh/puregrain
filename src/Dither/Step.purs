module Dither.Step where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Dither.Fifo (class Fifo, dequeue, enqueue)
import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K
import Dither.Pixel (class Scalable, Quantize(..), scale)
import Dither.State (RowLayer, RowState)
import Partial.Unsafe (unsafeCrashWith)

dequeueOne :: forall f a. Fifo f => f a -> Tuple a (f a)
dequeueOne fifo = case dequeue fifo of
  Nothing -> unsafeCrashWith "Dither.Step.dequeueOne: FIFO exhausted — padding/kernel invariant violated"
  Just { head, tail } -> Tuple head tail

dequeueAllLayer :: forall f a. Fifo f => RowLayer f a -> Tuple (Array a) (RowLayer f a)
dequeueAllLayer fifos = Tuple (map fst results) (map snd results)
  where
    results = map dequeueOne fifos

sumErrors :: forall a. Ring a => Array a -> a
sumErrors = Array.foldl (+) zero

enqueueWeighted :: forall f a. Fifo f => Scalable a => a -> K.Offset -> f a -> f a
enqueueWeighted err offset fifo = enqueue fifo (scale offset.weight err)

step
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => CompiledKernel
  -> Quantize a
  -> RowState f a
  -> a
  -> Tuple (RowState f a) a
step compiled (Quantize quantize) { current, matured, building } pixel =
  let
    Tuple currentErrs current' = dequeueAllLayer current

    maturedResults = map dequeueAllLayer matured
    maturedErrs = map fst maturedResults
    matured' = map snd maturedResults

    incomingError :: a
    incomingError =
      sumErrors currentErrs
        + Array.foldl (\acc errs -> acc + sumErrors errs) zero maturedErrs

    corrected = pixel + incomingError
    quantized = quantize corrected
    outErr    = corrected - quantized

    current'' = Array.zipWith (enqueueWeighted outErr) compiled.currentOffsets current'

    building' = Array.zipWith enqueueLayer compiled.futureLayers building
      where
        enqueueLayer offsets layer = Array.zipWith (enqueueWeighted outErr) offsets layer
  in
    Tuple { current: current'', matured: matured', building: building' } quantized