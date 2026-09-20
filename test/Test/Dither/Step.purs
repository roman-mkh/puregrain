module Test.Dither.Step where

import Prelude

import Data.List.Lazy as LL
import Data.Tuple (Tuple(..))
import Dither.Kernel (compileKernel, floydSteinberg)
import Dither.Kernel as K
import Dither.Pixel (Quantize(..))
import Dither.Row (initBuilding)
import Dither.State (RowLayer, RowState, freshLayer)
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
    initial :: RowState LL.List Number
    initial =
      { current: freshLayer (K.currentOffsets floydSteinberg)
      , matured:[[] :: (RowLayer LL.List Number)] 
      , building: initBuilding $ compileKernel floydSteinberg
      } 

    Tuple rowState1 quantizedPixel = step (compileKernel floydSteinberg) (Quantize quantizeThreshold) initial 100.0
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