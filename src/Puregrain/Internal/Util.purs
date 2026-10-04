-- | Small helpers. Internal: may change without notice.
module Puregrain.Internal.Util
  ( safeRange
  ) where

import Prelude

import Data.Array ((..))

-- | Like `(..)`, but returns `[]` when `lo > hi` instead of PureScript's
-- | native descending-range behaviour (`1 .. 0 == [1, 0]`, not `[]` —
-- | unlike Haskell's `[1..0] == []`). This codebase always wants the
-- | Haskell-like "empty when inverted" semantics: every call site
-- | builds a range from 1 up to some count that is legitimately allowed
-- | to be 0 (e.g. `maxDepth`), and expects zero elements in that case,
-- | not a spurious 2-element descending array.
safeRange :: Int -> Int -> Array Int
safeRange lo hi = if lo > hi then [] else lo .. hi