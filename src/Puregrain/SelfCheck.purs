-- | Checks that the JavaScript engine running the library computes its
-- | light curves (`Puregrain.Gamma`) exactly as the reference does, so that
-- | dithering with them gives the same results here as everywhere else.
-- |
-- | The curves use only operations that the JavaScript standard defines
-- | exactly, so every correct engine gives the same bits. This check makes
-- | sure, on the engine at hand: an engine with a fault in its arithmetic,
-- | or an optimizing compiler that changes it, would fail it. A pass means
-- | that this engine computed the reference values exactly: strong
-- | evidence, not proof for every value. Why and how:
-- | [docs/exact-arithmetic.md](https://github.com/roman-mkh/puregrain/blob/master/docs/exact-arithmetic.md).
-- |
-- | ```purescript
-- | report <- checkEngine
-- | unless (exactArithmetic report) do
-- |   for_ (problems report) log
-- | ```
module Puregrain.SelfCheck
  ( module Exports
  , checkEngine
  , exactArithmetic
  , problems
  ) where

import Prelude

import Data.Array as Array
import Effect (Effect)

import Puregrain.Internal.SelfCheck (EngineReport) as Exports
import Puregrain.Internal.SelfCheck (EngineReport(..), fingerprint, referenceDigests, reportFor, roundTripProblems)

-- | Runs the check on this engine.
-- |
-- | Returns the report. It takes a fraction of a second: each of the four
-- | computed curves is converted both ways for about 200,000 values, so
-- | that the engine's optimizing compilers run too. Nothing runs until
-- | it's called.
checkEngine :: Effect EngineReport
checkEngine = map (\_ -> reportFor referenceDigests (fingerprint unit) (roundTripProblems unit)) (pure unit)

-- | Whether the engine computed every reference value exactly.
exactArithmetic :: EngineReport -> Boolean
exactArithmetic (EngineReport report) = Array.null report.problems

-- | What failed, one sentence for each problem; empty when everything
-- | passed. Each names the curve and direction, or the byte, concerned.
problems :: EngineReport -> Array String
problems (EngineReport report) = report.problems
