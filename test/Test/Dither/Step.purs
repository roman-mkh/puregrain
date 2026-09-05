module Test.Dither.Step where

import Prelude

import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Test.Assert (assertEqual, assert')

import Dither.Kernel (floydSteinberg)
import Dither.State (initState)
import Dither.Step (step)
import Test.Util (approxArrayEqual, takeAsArray)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

main :: Effect Unit
main = do
  let
    state0 = initState floydSteinberg
    Tuple state1 quantizedPixel = step floydSteinberg quantizeThreshold state0 100.0
    outErr = 100.0

  assertEqual { actual: quantizedPixel, expected: 0.0 }

  case state1.current of
    [ f ] ->
      assert' "current prefix mismatch"
        (approxArrayEqual (takeAsArray 1 f) [ outErr * (7.0 / 16.0) ])
    _ -> log "FAIL: unexpected current shape"

  case state1.future of
    [ f1, f2, f3 ] -> do
      assert' "future[0] prefix mismatch"
        (approxArrayEqual (takeAsArray 1 f1) [ outErr * (3.0 / 16.0) ])
      assert' "future[1] prefix mismatch"
        (approxArrayEqual (takeAsArray 1 f2) [ outErr * (5.0 / 16.0) ])
      assert' "future[2] prefix mismatch"
        (approxArrayEqual (takeAsArray 2 f3) [ 0.0, outErr * (1.0 / 16.0) ])
    _ -> log "FAIL: unexpected future shape"

  log "All step tests passed"