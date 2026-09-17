module Test.Dither.Playground where

import Prelude

import Data.List.Lazy as LL
import Dither.Image (ditherImage)
import Dither.Kernel (atkinson, compileKernel, floydSteinberg, jarvisJudiceNinke)
import Dither.Kernel as K
import Dither.State (initState, freshLayer)

quantizeThreshold :: Number -> Number
quantizeThreshold x = if x < 128.0 then 0.0 else 255.0

fsState = initState (compileKernel floydSteinberg)

fsCurrent = freshLayer (K.currentOffsets floydSteinberg)

-- | Тестовое изображение 5x5, значения яркости 0-255.
testImage5x5 :: LL.List (Array Number) 
testImage5x5 = LL.fromFoldable
  [ [ 100.0, 150.0, 200.0, 80.0,  40.0  ]
  , [ 50.0,  180.0, 90.0,  210.0, 130.0 ]
  , [ 210.0, 60.0,  120.0, 30.0,  170.0 ]
  , [ 20.0,  140.0, 250.0, 100.0, 60.0  ]
  , [ 190.0, 70.0,  10.0,  160.0, 220.0 ]
  ]

atkinsonResult :: LL.List (Array Number)
atkinsonResult = ditherImage atkinson quantizeThreshold testImage5x5