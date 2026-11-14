-- | `Quantize`'s inside, for the drivers that resolve a quantizer once per
-- | run. Internal: may change without notice. `Puregrain.Quantize`
-- | re-exports the type, opaquely, with its constructors and runner.
module Puregrain.Internal.Quantize
  ( Quantize(..)
  , Context
  , Quantizer
  , quantizerFor
  ) where

import Puregrain.Internal.Gamma (Conversion)

-- | A quantizer: picks a pixel's output value; `a` is the pixel type.
-- | Build one with `quantize`, or `quantizeWith` when the decision depends
-- | on the pixel's position; run one with `runQuantize`. Opaque, so its
-- | representation can change without breaking anyone.
-- |
-- | It gets the pixel's corrected value, with the error diffused into it
-- | already added, and must be total: accumulated error pushes values
-- | beyond the nominal range, below 0 or above 255, and the quantizer must
-- | still return a sensible value. `ditherImage` diffuses the difference
-- | between the corrected value and the output to the neighbours.
-- Inside: a function of the driver's conversion between stored values and
-- light, called once per run, before the first pixel, so that whatever
-- the quantizer prepares (converted levels, say) is prepared once. (The
-- comment above is what Pursuit shows, through the re-export.)
newtype Quantize a = Quantize (Conversion a -> Context -> a -> a)

-- | Where the pixel being quantized sits: column `x` and row `y`, from 0
-- | at the top-left. A record so it can grow, with a seed say, without
-- | breaking quantizers: a helper that needs only some fields can take
-- | `forall r. { x :: Int, y :: Int | r }`.
type Context = { x :: Int, y :: Int }

-- | A quantizer resolved for one run: what the core calls for each pixel.
type Quantizer a = Context -> a -> a

-- | A quantizer resolved with the driver's conversion, once per run. Bind
-- | the result and call it for every pixel: calling `quantizerFor` again
-- | for each pixel would redo the quantizer's preparation each time, since
-- | PureScript shares nothing by itself.
quantizerFor :: forall a. Conversion a -> Quantize a -> Quantizer a
quantizerFor conversion (Quantize q) = q conversion
