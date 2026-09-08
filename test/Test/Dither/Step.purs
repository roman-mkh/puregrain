module Test.Dither.Step where

import Prelude

import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Test.Assert (assertEqual, assert')

import Dither.Kernel (floydSteinberg)
import Dither.Kernel as K
import Dither.State (freshLayer, initState, RowState)
import Dither.Step (step)
import Test.Util (approxArrayEqual, takeAsArray, takeLayersAsArray)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

main :: Effect Unit
main = do
  let
    initCurrent = freshLayer (K.currentOffsets floydSteinberg)
    state0 = initState floydSteinberg
    initial :: RowState
    initial = Tuple initCurrent state0.delayLines

    Tuple (Tuple current1 delayLines1) quantizedPixel =
      step floydSteinberg quantizeThreshold initial 100.0
    outErr = 100.0

  assertEqual { actual: quantizedPixel, expected: 0.0 }

  case current1 of
    [ f ] ->
      assert' "current prefix mismatch"
        (approxArrayEqual (takeAsArray 1 f) [ outErr * (7.0 / 16.0) ])
    _ -> log "FAIL: unexpected current shape"

  -- delayLines: 1 DelayLine (dy=1). Исходный слой был единственным
  -- элементом (снят как maturedLayer), укороченный хвост стал пустым,
  -- в него дописан ровно 1 новый RowLayer.
  case delayLines1 of
    [ dl ] -> do
      let layers = takeLayersAsArray 1 dl
      case layers of
        [ newLayer ] ->
          case newLayer of
            [ f1, f2, f3 ] -> do
              assert' "future dx=-1 mismatch"
                (approxArrayEqual (takeAsArray 1 f1) [ outErr * (3.0 / 16.0) ])
              assert' "future dx=0 mismatch"
                (approxArrayEqual (takeAsArray 1 f2) [ outErr * (5.0 / 16.0) ])
              assert' "future dx=1 mismatch"
                (approxArrayEqual (takeAsArray 1 f3) [ outErr * (1.0 / 16.0) ])
            _ -> log "FAIL: unexpected newLayer shape"
        _ -> log "FAIL: unexpected delayLine length"
    _ -> log "FAIL: unexpected delayLines shape"

  log "All step tests passed"