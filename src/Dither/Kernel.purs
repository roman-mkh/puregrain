module Dither.Kernel
  ( Kernel
  , Offset
  , floydSteinberg
  , atkinson
  , jarvisJudiceNinke
  , currentOffsets
  , futureOffsets
  , maxDepth
  , minDx
  , paddingFor
  , skipFor
  , layeredFutureOffsets
  )
  where

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

futureOffsets :: Kernel -> Array Offset
futureOffsets = Array.filter (\o -> o.dy > 0)

minDx :: Array Offset -> Int
minDx offsets = Array.foldl (\acc o -> min acc o.dx) 0 offsets

paddingFor :: Offset -> Int
paddingFor o = max 0 o.dx

skipFor :: Offset -> Int
skipFor o = max 0 (negate o.dx)

maxDepth :: Kernel -> Int
maxDepth kernel =
  Array.foldl (\acc o -> max acc o.dy) 0 kernel

-- | Группирует future-offset'ы (dy > 0) по значению dy, в слои от dy=1 до dy=maxDepth.
-- | Слой i (0-indexed) содержит все offset'ы с dy == i + 1, в исходном порядке.
-- | Слои для dy, у которых нет offset'ов в kernel, будут пустыми массивами.
layeredFutureOffsets :: Kernel -> Array (Array Offset)
layeredFutureOffsets kernel =
  map (\dy -> Array.filter (\o -> o.dy == dy) offsets) (1 .. depth)
  where
    offsets = futureOffsets kernel
    depth = maxDepth kernel  