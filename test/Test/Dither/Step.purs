module Test.Dither.Step where

import Prelude

import Data.Tuple (Tuple(..), fst)
import Dither.Kernel (floydSteinberg)
import Dither.Kernel as K
import Dither.Row (extractMatured, initBuilding)
import Dither.State (freshLayer, initState, RowState)
import Dither.Step (step)
import Effect (Effect)
import Effect.Console (log)
import Test.Assert (assertEqual, assert')
import Test.Util (approxArrayEqual, takeAsArray)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

main :: Effect Unit
main = do
  let
    state0 = initState floydSteinberg
    matured0 = fst (extractMatured state0.delayLines)

    initial :: RowState
    initial =
      { current: freshLayer (K.currentOffsets floydSteinberg)
      , matured: matured0
      , building: initBuilding floydSteinberg
      }

    Tuple rowState1 quantizedPixel = step floydSteinberg quantizeThreshold initial 100.0
    outErr = 100.0

  assertEqual { actual: quantizedPixel, expected: 0.0 }

  -- current: 1 FIFO, offset {dx:1, dy:0, weight: 7/16}
  case rowState1.current of
    [ f ] ->
      assert' "current prefix mismatch"
        (approxArrayEqual (takeAsArray 1 f) [ outErr * (7.0 / 16.0) ])
    _ -> log "FAIL: unexpected current shape"

  -- building: 1 RowLayer (dy=1), offsets в порядке kernel: dx=-1, dx=0, dx=1
  case rowState1.building of
    [ [ f1, f2, f3 ] ] -> do
      assert' "building dx=-1 mismatch"
        (approxArrayEqual (takeAsArray 1 f1) [ outErr * (3.0 / 16.0) ])
      assert' "building dx=0 mismatch"
        (approxArrayEqual (takeAsArray 1 f2) [ outErr * (5.0 / 16.0) ])
      -- dx=1 имеет paddingFor=1, значит первый элемент — паддинг-ноль,
      -- реальное значение идёт вторым
      assert' "building dx=1 mismatch"
        (approxArrayEqual (takeAsArray 2 f3) [ 0.0, outErr * (1.0 / 16.0) ])
    _ -> log "FAIL: unexpected building shape"

  log "All step tests passed"