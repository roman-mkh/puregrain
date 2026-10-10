-- | The clock around the dithering, as a small JS foreign module.
-- |
-- | It's foreign on purpose. Timed in PureScript (read the clock, compute,
-- | read it again), the measurement relies on pure code running exactly
-- | where it's written. purs keeps that order, but an optimizing backend
-- | may move pure code: purs-backend-es moved the dithering after the
-- | second clock read (0.0 ms measured). Code inside a foreign function
-- | can't be moved.
module Puregrain.Cli.Timing
  ( timed
  ) where

import Effect (Effect)

-- | `timed f x` computes `f x` between two reads of a high-resolution
-- | monotonic clock (`performance.now`) and returns the elapsed
-- | milliseconds with the result. `x` is passed separately, so it's
-- | computed before the first read: only `f` is measured.
foreign import timed :: forall a b. (a -> b) -> a -> Effect { ms :: Number, result :: b }
