module Dither.Fifo.Generic where

import Prelude

import Data.Array as Array
import Data.Foldable (class Foldable)
import Data.Maybe (Maybe)
import Data.Unfoldable (class Unfoldable)
import Data.Unfoldable as Unfoldable
{- 
-- | Generic, backend-agnostic fallback implementations of the four Fifo
-- | operations, requiring only Foldable+Unfoldable on f. NOT wired as an
-- | actual `instance Fifo f` (PureScript forbids overlapping instances) —
-- | each new type must explicitly reference these in its own instance
-- | declaration. Every operation round-trips through Array, so this is
-- | O(n) even for dequeue/enqueue — a convenience for quickly trying a
-- | new candidate type, not a substitute for a hand-written instance on
-- | anything performance-sensitive.

genericReplicate :: forall f. Unfoldable f => Int -> Number -> f Number
genericReplicate n x = Unfoldable.replicate n x

genericEnqueue :: forall f. Foldable f => Unfoldable f => f Number -> Number -> f Number
genericEnqueue fifo x =
  Unfoldable.fromFoldable (Array.snoc (Array.fromFoldable fifo) x)

genericDequeue :: forall f. Foldable f => Unfoldable f => f Number -> Maybe { head :: Number, tail :: f Number }
genericDequeue fifo =
  Array.uncons (Array.fromFoldable fifo) <#> \{ head, tail } ->
    { head, tail: Unfoldable.fromFoldable tail }

genericReplace :: forall f. Foldable f => Unfoldable f => Int -> f Number -> f Number
genericReplace skip fifo =
  let arr = Array.fromFoldable fifo
  in Unfoldable.fromFoldable (Array.drop skip arr <> Array.replicate skip 0.0) -}