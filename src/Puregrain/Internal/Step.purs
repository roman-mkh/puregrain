-- | One pixel of the diffusion: add up the error arriving from earlier
-- | pixels, quantize, and send the new error on to the queues.
-- | Internal: may change without notice.
module Puregrain.Internal.Step
  ( step
  , dequeueAllLayer
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Partial.Unsafe (unsafeCrashWith)
import Puregrain.Internal.Fifo (class Fifo, dequeue, enqueue)
import Puregrain.Internal.Kernel (CompiledKernel)
import Puregrain.Internal.State (RowLayer, RowState)
import Puregrain.Kernel (Offset)
import Puregrain.Pixel (class Scalable, scale)
import Puregrain.Quantize (Quantize, runQuantize)

dequeueOne :: forall f a. Fifo f => f a -> Tuple a (f a)
dequeueOne fifo = case dequeue fifo of
  Nothing -> unsafeCrashWith "Puregrain.Internal.Step.dequeueOne: FIFO exhausted - padding/kernel invariant violated"
  Just { head, tail } -> Tuple head tail

dequeueAllLayer :: forall f a. Fifo f => RowLayer f a -> Tuple (Array a) (RowLayer f a)
dequeueAllLayer fifos = Tuple (map fst results) (map snd results)
  where
    results = map dequeueOne fifos

sumErrors :: forall a. Ring a => Array a -> a
sumErrors = Array.foldl (+) zero

enqueueWeighted :: forall f a. Fifo f => Scalable a => a -> Offset -> f a -> f a
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
step compiled quantize { current, matured, building, x, y } pixel =
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
    quantized = runQuantize quantize { x, y } corrected
    outErr    = corrected - quantized

    current'' = Array.zipWith (enqueueWeighted outErr) compiled.currentOffsets current'

    building' = Array.zipWith enqueueLayer compiled.futureLayers building
      where
        enqueueLayer offsets layer = Array.zipWith (enqueueWeighted outErr) offsets layer
  in
    Tuple { current: current'', matured: matured', building: building', x: x + 1, y } quantized