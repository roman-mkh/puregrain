module Dither.Step where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Dither.Kernel (Kernel)
import Dither.Kernel as K
import Dither.State (Fifo, RowLayer, RowState)
import Partial.Unsafe (unsafeCrashWith)

dequeueOne :: Fifo -> Tuple Number Fifo
dequeueOne fifo = case LL.uncons fifo of
  Nothing -> unsafeCrashWith "Dither.Step.dequeueOne: FIFO exhausted — padding/kernel invariant violated"
  Just { head, tail } -> Tuple head tail

dequeueAllLayer :: RowLayer -> Tuple (Array Number) RowLayer
dequeueAllLayer fifos = Tuple (map fst results) (map snd results)
  where
    results = map dequeueOne fifos

sumErrors :: Array Number -> Number
sumErrors = Array.foldl (+) 0.0

enqueueWeighted :: Number -> K.Offset -> Fifo -> Fifo
enqueueWeighted err offset fifo = LL.snoc fifo (err * offset.weight)

step
  :: Kernel
  -> (Number -> Number)
  -> RowState
  -> Number
  -> Tuple RowState Number
step kernel quantize { current, matured, building } pixel =
  let
    Tuple currentErrs current' = dequeueAllLayer current

    maturedResults :: Array (Tuple (Array Number) RowLayer)
    maturedResults = map dequeueAllLayer matured

    maturedErrs :: Array (Array Number)
    maturedErrs = map fst maturedResults

    matured' :: Array RowLayer
    matured' = map snd maturedResults

    incomingError :: Number
    incomingError =
      sumErrors currentErrs
        + Array.foldl (\acc errs -> acc + sumErrors errs) 0.0 maturedErrs

    corrected = pixel + incomingError
    quantized = quantize corrected
    outErr    = corrected - quantized

    current'' :: RowLayer
    current'' = Array.zipWith (enqueueWeighted outErr) (K.currentOffsets kernel) current'

    depth :: Int
    depth = K.maxDepth kernel

    building' :: Array RowLayer
    building' = Array.zipWith enqueueLayerFor (1 .. depth) building
      where
        enqueueLayerFor :: Int -> RowLayer -> RowLayer
        enqueueLayerFor dy layer =
          Array.zipWith (enqueueWeighted outErr) (K.offsetsForDy kernel dy) layer
  in
    Tuple { current: current'', matured: matured', building: building' } quantized