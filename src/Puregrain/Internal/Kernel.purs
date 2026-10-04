-- | The compiled form of a kernel, built once per image so the per-pixel
-- | step doesn't filter the kernel again for every pixel (PureScript
-- | shares nothing automatically). Internal: may change without notice.
module Puregrain.Internal.Kernel
  ( CompiledKernel
  , compileKernel
  , paddingFor
  , skipFor
  ) where

import Prelude

import Data.Array as Array
import Puregrain.Internal.Util (safeRange)
import Puregrain.Kernel (Kernel, Offset, offsets)

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
  { currentOffsets: currentOffsets list
  , futureLayers:   layeredFutureOffsets list
  , maxDepth:       maxDepth list
  }
  where
    list = offsets kernel

currentOffsets :: Array Offset -> Array Offset
currentOffsets = Array.filter (\o -> o.dy == 0)

-- | The offsets of one later row (`dy > 0`).
offsetsForDy :: Array Offset -> Int -> Array Offset
offsetsForDy list dy = Array.filter (\o -> o.dy == dy) list

-- | The offsets of every later row, grouped by `dy` from 1 to `maxDepth`:
-- | layer i (counted from 0) holds the offsets with `dy == i + 1`.
layeredFutureOffsets :: Array Offset -> Array (Array Offset)
layeredFutureOffsets list = map (offsetsForDy list) (safeRange 1 (maxDepth list))

paddingFor :: Offset -> Int
paddingFor o = max 0 o.dx

skipFor :: Offset -> Int
skipFor o = max 0 (negate o.dx)

maxDepth :: Array Offset -> Int
maxDepth list =
  Array.foldl (\acc o -> max acc o.dy) 0 list
