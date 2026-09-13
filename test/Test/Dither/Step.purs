module Test.Dither.Step where

import Prelude

import Data.Tuple (Tuple(..), fst)
import Dither.Kernel (compileKernel, floydSteinberg)
import Dither.Kernel as K
import Dither.Row (extractMatured, initBuilding, resolveSeededLayer)
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
    width = 3   -- ширина строки для этого теста — нужна для resolveSeededLayer

    state0 = initState  $ compileKernel floydSteinberg
    matured0Seeded = fst (extractMatured state0.delayLines)
    matured0 = map (resolveSeededLayer width) matured0Seeded

    initial :: RowState
    initial =
      { current: freshLayer (K.currentOffsets floydSteinberg)
      , matured: matured0
      , building: initBuilding $ compileKernel floydSteinberg
      }

    Tuple rowState1 quantizedPixel = step (compileKernel floydSteinberg) quantizeThreshold initial 100.0
    outErr = 100.0

  assertEqual { actual: quantizedPixel, expected: 0.0 }

  case rowState1.current of
    [ f ] ->
      assert' "current prefix mismatch"
        (approxArrayEqual (takeAsArray 1 f) [ outErr * (7.0 / 16.0) ])
    _ -> log "FAIL: unexpected current shape"

  case rowState1.building of
    [ [ f1, f2, f3 ] ] -> do
      assert' "building dx=-1 mismatch"
        (approxArrayEqual (takeAsArray 1 f1) [ outErr * (3.0 / 16.0) ])
      assert' "building dx=0 mismatch"
        (approxArrayEqual (takeAsArray 1 f2) [ outErr * (5.0 / 16.0) ])
      assert' "building dx=1 mismatch"
        (approxArrayEqual (takeAsArray 2 f3) [ 0.0, outErr * (1.0 / 16.0) ])
    _ -> log "FAIL: unexpected building shape"

  log "All step tests passed"