module Test.Dither.Row where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.Tuple (Tuple(..))
import Dither.Kernel (compileKernel, floydSteinberg)
import Dither.Pixel (Quantize(..))
import Dither.Row (ditherRow)
import Dither.State (DitherState, initState)
import Effect (Effect)
import Effect.Console (log)
import Test.Assert (assertEqual, assert')

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0 

main :: Effect Unit
main = do
  let
    state0 :: DitherState LL.List Number
    state0 = initState $ compileKernel floydSteinberg
    row = [ 100.0, 200.0, 50.0 ]
    Tuple _delayLines1 quantizedRow =
      ditherRow (compileKernel floydSteinberg) (Quantize quantizeThreshold) state0.delayLines row

  assertEqual { actual: Array.length quantizedRow, expected: Array.length row }

  assert' "all quantized pixels are valid threshold values"
    (Array.all (\p -> p == 0.0 || p == 255.0) quantizedRow)

  log "All ditherRow tests passed"