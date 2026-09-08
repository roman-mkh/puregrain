module Dither.Kernel where

import Prelude

import Data.Array ((..))
import Data.Array as Array

type Offset =
  { dx     :: Int
  , dy     :: Int
  , weight :: Number
  }

type Kernel = Array Offset

floydSteinberg :: Kernel
floydSteinberg =
  [ { dx: 1,  dy: 0, weight: 7.0 / 16.0 }
  , { dx: -1, dy: 1, weight: 3.0 / 16.0 }
  , { dx: 0,  dy: 1, weight: 5.0 / 16.0 }
  , { dx: 1,  dy: 1, weight: 1.0 / 16.0 }
  ]

atkinson :: Kernel
atkinson =
  [ { dx: 1,  dy: 0, weight: 1.0 / 8.0 }
  , { dx: 2,  dy: 0, weight: 1.0 / 8.0 }
  , { dx: -1, dy: 1, weight: 1.0 / 8.0 }
  , { dx: 0,  dy: 1, weight: 1.0 / 8.0 }
  , { dx: 1,  dy: 1, weight: 1.0 / 8.0 }
  , { dx: 0,  dy: 2, weight: 1.0 / 8.0 }
  ]

jarvisJudiceNinke :: Kernel
jarvisJudiceNinke =
  [ { dx: 1, dy: 0, weight: 7.0 / 48.0 }
  , { dx: 2, dy: 0, weight: 5.0 / 48.0 }

  , { dx: -2, dy: 1, weight: 3.0 / 48.0 }
  , { dx: -1, dy: 1, weight: 5.0 / 48.0 }
  , { dx: 0,  dy: 1, weight: 7.0 / 48.0 }
  , { dx: 1,  dy: 1, weight: 5.0 / 48.0 }
  , { dx: 2,  dy: 1, weight: 3.0 / 48.0 }

  , { dx: -2, dy: 2, weight: 1.0 / 48.0 }
  , { dx: -1, dy: 2, weight: 3.0 / 48.0 }
  , { dx: 0,  dy: 2, weight: 5.0 / 48.0 }
  , { dx: 1,  dy: 2, weight: 3.0 / 48.0 }
  , { dx: 2,  dy: 2, weight: 1.0 / 48.0 }
  ]

currentOffsets :: Kernel -> Array Offset
currentOffsets = Array.filter (\o -> o.dy == 0)

-- | Offset'ы, относящиеся к конкретному значению dy (dy > 0).
offsetsForDy :: Kernel -> Int -> Array Offset
offsetsForDy kernel dy = Array.filter (\o -> o.dy == dy) kernel

-- | Offset'ы, сгруппированные по dy, для dy от 1 до maxDepth.
-- | Слой i (0-indexed) содержит offset'ы с dy == i + 1.
layeredFutureOffsets :: Kernel -> Array (Array Offset)
layeredFutureOffsets kernel = map (offsetsForDy kernel) (1 .. maxDepth kernel)

paddingFor :: Offset -> Int
paddingFor o = max 0 o.dx

skipFor :: Offset -> Int
skipFor o = max 0 (negate o.dx)

maxForward :: Kernel -> Int
maxForward kernel =
  Array.foldl (\acc o -> if o.dy == 0 then max acc o.dx else acc) 0 kernel

maxDepth :: Kernel -> Int
maxDepth kernel =
  Array.foldl (\acc o -> max acc o.dy) 0 kernel
  