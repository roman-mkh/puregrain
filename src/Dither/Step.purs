module Dither.Step where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..), fst, snd)
import Dither.Kernel (Kernel)
import Dither.Kernel as K
import Dither.State (DelayLine, Fifo, RowLayer, RowState)
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
step kernel quantize (Tuple current delayLines) pixel =
  let
    fronts :: Array (Tuple RowLayer DelayLine)
    fronts = map takeFront delayLines
      where
        takeFront :: DelayLine -> Tuple RowLayer DelayLine
        takeFront dl = case LL.uncons dl of
          Nothing -> unsafeCrashWith "Dither.Step: delayLine unexpectedly empty"
          Just { head, tail } -> Tuple head tail

    maturedLayers :: Array RowLayer
    maturedLayers = map fst fronts

    anticipatedDelayLines :: Array DelayLine
    anticipatedDelayLines = map snd fronts

    Tuple currentErrs current' = dequeueAllLayer current

    maturedResults :: Array (Tuple (Array Number) RowLayer)
    maturedResults = map dequeueAllLayer maturedLayers

    maturedErrs :: Array (Array Number)
    maturedErrs = map fst maturedResults

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

    newLayers :: Array RowLayer
    newLayers = map buildNewLayerFor (1 .. depth)
      where
        buildNewLayerFor :: Int -> RowLayer
        buildNewLayerFor dy =
          map (\o -> LL.singleton (outErr * o.weight)) (K.offsetsForDy kernel dy)

    delayLines' :: Array DelayLine
    delayLines' = Array.zipWith LL.snoc anticipatedDelayLines newLayers
  in
    Tuple (Tuple current'' delayLines') quantized