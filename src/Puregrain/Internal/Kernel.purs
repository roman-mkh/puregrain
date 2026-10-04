-- | The compiled form of a kernel, built once per image so the per-pixel
-- | step doesn't filter the kernel again for every pixel (PureScript
-- | shares nothing automatically). Internal: may change without notice.
module Puregrain.Internal.Kernel
  ( CompiledKernel
  , compileKernel
  , currentOffsets
  , paddingFor
  , skipFor
  , maxDepth
  ) where

import Prelude

import Data.Array as Array
import Puregrain.Internal.Util (safeRange)
import Puregrain.Kernel (Kernel, Offset)

-- | Precomputed per kernel: the offsets in the current row, the offsets
-- | of each later row grouped by `dy` (layer i holds those with
-- | `dy == i + 1`), and the deepest `dy`. Built once by `compileKernel`,
-- | then passed on as plain data through the row and step code.
type CompiledKernel =
  { currentOffsets :: Array Offset
  , futureLayers   :: Array (Array Offset)
  , maxDepth       :: Int
  }

compileKernel :: Kernel -> CompiledKernel
compileKernel kernel =
  { currentOffsets: currentOffsets kernel
  , futureLayers:   layeredFutureOffsets kernel
  , maxDepth:       maxDepth kernel
  }

currentOffsets :: Kernel -> Array Offset
currentOffsets = Array.filter (\o -> o.dy == 0)

-- | The offsets of one later row (`dy > 0`).
offsetsForDy :: Kernel -> Int -> Array Offset
offsetsForDy kernel dy = Array.filter (\o -> o.dy == dy) kernel

-- | The offsets of every later row, grouped by `dy` from 1 to `maxDepth`:
-- | layer i (counted from 0) holds the offsets with `dy == i + 1`.
layeredFutureOffsets :: Kernel -> Array (Array Offset)
layeredFutureOffsets kernel = map (offsetsForDy kernel) (safeRange 1 (maxDepth kernel))

paddingFor :: Offset -> Int
paddingFor o = max 0 o.dx

skipFor :: Offset -> Int
skipFor o = max 0 (negate o.dx)

maxDepth :: Kernel -> Int
maxDepth kernel =
  Array.foldl (\acc o -> max acc o.dy) 0 kernel
