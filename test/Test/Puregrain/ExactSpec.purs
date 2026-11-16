module Test.Puregrain.ExactSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Foldable (and, for_)
import Data.Int (toNumber)
import Data.Number (infinity, isFinite, isNaN)
import Data.Ord (abs)
import Test.QuickCheck ((<?>), (===))
import Test.QuickCheck.Gen (Gen, choose, chooseInt, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck, quickCheck')

import Puregrain.Internal.Exact (cubeRoot, cubeRootStep, fifthRoot, fifthRootStep)

-- | 2 to the power of `e`, exactly: doubling and halving lose nothing.
twoTo :: Int -> Number
twoTo e
  | e > 0 = 2.0 * twoTo (e - 1)
  | e < 0 = twoTo (e + 1) / 2.0
  | otherwise = 1.0

-- | A positive number of any magnitude, from 2^-100 to 2^101.
genMagnitude :: Gen Number
genMagnitude = (\m e -> m * twoTo e) <$> choose 1.0 2.0 <*> chooseInt (-100) 100

-- | The values Newton's steps from 1 keep visiting once they've settled:
-- | the last 8 of 60 steps, far more than any value needs.
settledValues :: (Number -> Number -> Number) -> Number -> Array Number
settledValues step m = Array.drop 52 (Array.scanl (\y _ -> step m y) 1.0 (1 .. 60))

-- | `steps` evenly spaced values in [low, 1): the range the roots reduce
-- | every input to.
grid :: Int -> Number -> Array Number
grid steps low = map (\i -> low + (1.0 - low) * toNumber i / toNumber steps) (0 .. (steps - 1))

-- | x to the power of n, by multiplication.
power :: Int -> Number -> Number
power n x = Array.foldl (\acc _ -> acc * x) 1.0 (1 .. n)

relativeError :: Number -> Number -> Number
relativeError actual expected = abs (actual - expected) / expected

-- | The gap between `y` (positive) and the next larger number: 2^-52 of
-- | the power of 2 at or below `y`, found by exact halving and doubling.
unitInLastPlace :: Number -> Number
unitInLastPlace y = go 1.0
  where
  go p
    | p > y = go (p / 2.0)
    | p * 2.0 <= y = go (p * 2.0)
    | otherwise = p * 2.220446049250313e-16

-- | Whether `f` never gives a smaller result for a larger number, except
-- | by up to two units in the last place: where Newton's steps end on a
-- | bounce between two results (sometimes two units apart), neighbouring
-- | numbers can get them in either order (docs/exact-arithmetic.md).
risesWithinTwoUnits :: (Number -> Number) -> Array Number -> Boolean
risesWithinTwoUnits f xs = and (Array.zipWith ok sorted (Array.drop 1 sorted))
  where
  sorted = Array.sort xs
  ok a b = f b >= f a - 2.0 * unitInLastPlace (f a)

-- | Values on both sides of the reduction's boundaries, as written down
-- | here (1/32 and 1/8, 1, 8 and 32, and their neighbouring numbers).
boundaries :: Array Number
boundaries =
  [ 0.03125, 0.031249999999999997, 0.03125000000000001
  , 0.125, 0.12499999999999999, 0.12500000000000003
  , 1.0, 0.9999999999999999, 1.0000000000000002
  , 8.0, 7.999999999999999, 8.000000000000002
  , 32.0, 31.999999999999996, 32.00000000000001
  ]

spec :: Spec Unit
spec = describe "Puregrain.Internal.Exact" do
  for_
    [ { name: "fifthRoot", root: fifthRoot, step: fifthRootStep, degree: 5, base: 32.0, worst: 2.0e-15, perfect: 1000 }
    , { name: "cubeRoot", root: cubeRoot, step: cubeRootStep, degree: 3, base: 8.0, worst: 1.2e-15, perfect: 10000 }
    ]
    \r -> describe r.name do

      it "has settled within its steps, over the range it reduces to" do
        let
          unsettled = Array.filter (\m -> not (Array.elem (r.root m) (settledValues r.step m))) (grid 20000 (1.0 / r.base))
        unsettled `shouldEqual` []
        quickCheck' 1000 do
          m <- choose (1.0 / r.base) 1.0
          pure (Array.elem (r.root m) (settledValues r.step m) <?> ("not settled for " <> show m))

      it "is accurate to within two units in the last place" do
        quickCheck' 1000 do
          x <- genMagnitude
          let err = relativeError (power r.degree (r.root x)) x
          pure (err <= r.worst <?> ("relative error " <> show err <> " for " <> show x))

      it "gives perfect powers exactly" do
        let wrong = Array.filter (\k -> r.root (power r.degree (toNumber k)) /= toNumber k) (1 .. r.perfect)
        wrong `shouldEqual` []

      it "scales exactly: the root of base * x is twice the root of x" do
        quickCheck do
          x <- genMagnitude
          pure (r.root (r.base * x) === 2.0 * r.root x)

      it "is odd: the root of -x is minus the root of x" do
        quickCheck do
          x <- genMagnitude
          pure (r.root (negate x) === negate (r.root x))

      it "rises, though neighbouring numbers may come out up to two units in the last place apart in either order" do
        risesWithinTwoUnits r.root boundaries `shouldEqual` true
        quickCheck do
          xs <- vectorOf 250 genMagnitude
          let neighbours = map (_ * 1.0000000000000002) xs
          pure (risesWithinTwoUnits r.root (xs <> neighbours <> boundaries) <?> "a larger number got a root more than two units smaller")

      it "keeps the order of numbers a millionth apart" do
        quickCheck do
          x <- genMagnitude
          pure (r.root (x * 1.000001) > r.root x <?> ("the order is lost at " <> show x))

      it "keeps 0, the infinities and NaN, and takes the smallest numbers" do
        r.root 0.0 `shouldEqual` 0.0
        r.root infinity `shouldEqual` infinity
        r.root (negate infinity) `shouldEqual` negate infinity
        r.root (0.0 / 0.0) `shouldSatisfy` isNaN
        r.root 5.0e-324 `shouldSatisfy` \y -> isFinite y && y > 0.0
        r.root 1.7976931348623157e308 `shouldSatisfy` \y -> isFinite y && y > 0.0
        r.root 1.0 `shouldEqual` 1.0
        r.root (1.0 / r.base) `shouldEqual` 0.5
        when (r.root r.base /= 2.0) (fail "the root of the base isn't 2")
