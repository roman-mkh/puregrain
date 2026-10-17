-- | Small helpers. Internal: may change without notice.
module Puregrain.Internal.Util
  ( safeRange
  , isGrid
  , sizeOf
  ) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Maybe (maybe)

-- | Like `(..)`, but returns `[]` when `lo > hi` instead of PureScript's
-- | native descending-range behaviour (`1 .. 0 == [1, 0]`, not `[]` —
-- | unlike Haskell's `[1..0] == []`). This codebase always wants the
-- | Haskell-like "empty when inverted" semantics: every call site
-- | builds a range from 1 up to some count that is legitimately allowed
-- | to be 0 (e.g. `maxDepth`), and expects zero elements in that case,
-- | not a spurious 2-element descending array.
safeRange :: Int -> Int -> Array Int
safeRange lo hi = if lo > hi then [] else lo .. hi

-- | Whether the rows form a grid of exactly `width` × `height`.
isGrid :: forall a. Int -> Int -> Array (Array a) -> Boolean
isGrid width height rows = Array.length rows == height && Array.all (\row -> Array.length row == width) rows

-- | "width x height", or, for rows of different lengths, how many rows:
-- | for a message about a grid of the wrong size.
sizeOf :: forall a. Array (Array a) -> String
sizeOf rows =
  if Array.all (\row -> Array.length row == width) rows then show width <> "x" <> show (Array.length rows)
  else show (Array.length rows) <> " rows of different lengths"
  where
  width = maybe 0 Array.length (Array.head rows)
