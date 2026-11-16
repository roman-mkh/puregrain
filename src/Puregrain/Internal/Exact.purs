-- | Fifth and cube roots from exact operations only (+, −, ×, ÷ and
-- | comparisons), so that every JavaScript engine gives the same results:
-- | ECMA-262 lets `Math.pow` and `Math.cbrt` differ between engines, but
-- | not these operations. Internal: may change without notice.
-- |
-- | Each root scales its input by exact powers of 2 into a small range,
-- | [1/32, 1) for the fifth root and [1/8, 1) for the cube root, takes a
-- | fixed number of Newton's steps from 1, and scales back. Scaling by
-- | powers of 2 loses nothing, so the same number of steps fits every
-- | input, from the smallest denormal up, and `fifthRoot (32.0 * x)` is
-- | exactly `2.0 * fifthRoot x`.
-- |
-- | The results are within two units in the last place of the nearest
-- | number to the true root, mostly that number itself, so two neighbouring
-- | inputs can get roots up to two units apart in either order. Why, how
-- | often, and why it doesn't matter for dithering:
-- | docs/exact-arithmetic.md.
module Puregrain.Internal.Exact
  ( fifthRoot
  , cubeRoot
  , fifthRootStep
  , cubeRootStep
  ) where

import Prelude

import Data.Number (isFinite)

-- The step counts: the most that any reduced value needed until it
-- settled, measured over 400,000 values (9 for the fifth root, 8 for the
-- cube root, 2026-11-14), plus one step of margin, as agreed with the user
-- (linear light's decision 2, in CLAUDE.md). Settled means that further
-- steps keep the value, or bounce between it and a neighbouring number;
-- either way every engine gets the same result.
fifthRootSteps :: Int
fifthRootSteps = 10

cubeRootSteps :: Int
cubeRootSteps = 9

-- | The fifth root of any number. Odd: a negative number's root is the
-- | negative of its magnitude's root. 0, the infinities and NaN come back
-- | as they are.
fifthRoot :: Number -> Number
fifthRoot x =
  if x == 0.0 || not (isFinite x) then x
  else if x < 0.0 then negate (fifthRoot (negate x))
  else fifthDown 1.0 x

-- | The cube root of any number, as `fifthRoot` is the fifth.
cubeRoot :: Number -> Number
cubeRoot x =
  if x == 0.0 || not (isFinite x) then x
  else if x < 0.0 then negate (cubeRoot (negate x))
  else cubeDown 1.0 x

-- | One of Newton's steps towards the fifth root of `m`, from `y`.
fifthRootStep :: Number -> Number -> Number
fifthRootStep m y = (4.0 * y + m / (y2 * y2)) / 5.0
  where
  y2 = y * y

-- | One of Newton's steps towards the cube root of `m`, from `y`.
cubeRootStep :: Number -> Number -> Number
cubeRootStep m y = (2.0 * y + m / (y * y)) / 3.0

-- Each root has its own loops, with its Newton step written out, rather
-- than one general loop taking the step and the base as arguments: purs
-- compiles every call of a function passed as an argument into curried
-- calls that build a closure each, about 20 per root, which made the roots
-- three times slower (2026-11-14). The operations and their order are the
-- steps' above, so the results are the same, bit for bit: checked against
-- the general version over 2 million inputs of every size.

-- Into [1/32, 1): down for 1 and above, then up for values below 1/32;
-- `scale` keeps the matching power of 2. 32 = 2^5, so dividing the input
-- by 32 halves its fifth root, exactly.
fifthDown :: Number -> Number -> Number
fifthDown scale m =
  if m >= 1.0 then fifthDown (scale * 2.0) (m / 32.0)
  else fifthUp scale m

fifthUp :: Number -> Number -> Number
fifthUp scale m =
  if m < 1.0 / 32.0 then fifthUp (scale / 2.0) (m * 32.0)
  else scale * fifthNewton fifthRootSteps m 1.0

-- `fifthRootStep`, written out: (y * y) * (y * y) is its y2 * y2.
fifthNewton :: Int -> Number -> Number -> Number
fifthNewton n m y =
  if n <= 0 then y
  else fifthNewton (n - 1) m ((4.0 * y + m / (y * y * (y * y))) / 5.0)

-- As for the fifth root, with 8 = 2^3 and [1/8, 1).
cubeDown :: Number -> Number -> Number
cubeDown scale m =
  if m >= 1.0 then cubeDown (scale * 2.0) (m / 8.0)
  else cubeUp scale m

cubeUp :: Number -> Number -> Number
cubeUp scale m =
  if m < 1.0 / 8.0 then cubeUp (scale / 2.0) (m * 8.0)
  else scale * cubeNewton cubeRootSteps m 1.0

-- `cubeRootStep`, written out.
cubeNewton :: Int -> Number -> Number -> Number
cubeNewton n m y =
  if n <= 0 then y
  else cubeNewton (n - 1) m ((2.0 * y + m / (y * y)) / 3.0)
