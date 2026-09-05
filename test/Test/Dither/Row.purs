module Test.Dither.Row where

import Prelude

import Data.Array as Array
import Data.Tuple (Tuple(..))
import Effect (Effect)
import Effect.Console (log)
import Test.Assert (assertEqual, assert')

import Dither.Kernel (floydSteinberg)
import Dither.State (initState)
import Dither.Row (ditherRow)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0
 
main :: Effect Unit
main = do
  let
    state0 = initState floydSteinberg
    row = [ 100.0, 200.0, 50.0 ]
    Tuple _state1 quantizedRow = ditherRow floydSteinberg quantizeThreshold state0 row

  -- длина результата должна совпадать со входом
  assertEqual { actual: Array.length quantizedRow, expected: Array.length row }

  -- каждый квантованный пиксель должен быть либо 0, либо 255 (для порогового quantize)
  assert' "all quantized pixels are valid threshold values"
    (Array.all (\p -> p == 0.0 || p == 255.0) quantizedRow)

  log "All ditherRow tests passed"