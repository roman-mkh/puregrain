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
-- (docs/linear-light-spec.md, decision 2). Settled means that further
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
fifthRoot = rootBy 32.0 fifthRootSteps fifthRootStep

-- | The cube root of any number, as `fifthRoot` is the fifth.
cubeRoot :: Number -> Number
cubeRoot = rootBy 8.0 cubeRootSteps cubeRootStep

-- | One of Newton's steps towards the fifth root of `m`, from `y`.
fifthRootStep :: Number -> Number -> Number
fifthRootStep m y = (4.0 * y + m / (y2 * y2)) / 5.0
  where
  y2 = y * y

-- | One of Newton's steps towards the cube root of `m`, from `y`.
cubeRootStep :: Number -> Number -> Number
cubeRootStep m y = (2.0 * y + m / (y * y)) / 3.0

-- `base` is 2 to the power of the root's degree (32 or 8), so dividing
-- the input by `base` halves the root, exactly.
rootBy :: Number -> Int -> (Number -> Number -> Number) -> Number -> Number
rootBy base steps step x =
  if x == 0.0 || not (isFinite x) then x
  else if x < 0.0 then negate (rootBy base steps step (negate x))
  else scaleDown base steps step 1.0 x

-- Into [1/base, 1): down for 1 and above, then up for values below
-- 1/base; `scale` keeps the matching power of 2.
scaleDown :: Number -> Int -> (Number -> Number -> Number) -> Number -> Number -> Number
scaleDown base steps step scale m =
  if m >= 1.0 then scaleDown base steps step (scale * 2.0) (m / base)
  else scaleUp base steps step scale m

scaleUp :: Number -> Int -> (Number -> Number -> Number) -> Number -> Number -> Number
scaleUp base steps step scale m =
  if m < 1.0 / base then scaleUp base steps step (scale / 2.0) (m * base)
  else scale * newton step steps m 1.0

newton :: (Number -> Number -> Number) -> Int -> Number -> Number -> Number
newton step n m y =
  if n <= 0 then y
  else newton step (n - 1) m (step m y)
