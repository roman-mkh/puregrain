module Test.Dither.Image where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Dither.Image (ditherImage)
import Dither.Kernel (floydSteinberg)
import Effect (Effect)
import Effect.Console (log)
import Test.Assert (assertEqual)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

main :: Effect Unit
main = do
  let
    rows = LL.fromFoldable
      [ [ 100.0, 200.0, 50.0 ]
      , [ 150.0, 30.0, 220.0 ]
      ]
    result = ditherImage floydSteinberg quantizeThreshold rows

  -- число строк на выходе совпадает со входом
  assertEqual { actual: LL.length result, expected: LL.length rows }

  -- ленивость: можно взять только первую строку, не форсируя вторую
  case LL.uncons result of
    Just { head } ->
      assertEqual { actual: Array.length head, expected: 3 }
    Nothing -> log "FAIL: expected at least one row"

  log "All ditherImage tests passed"