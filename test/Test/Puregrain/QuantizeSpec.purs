module Test.Puregrain.QuantizeSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Data.Ord (abs)
import Test.QuickCheck (Result(..), arbitrary, (===))
import Test.QuickCheck.Gen (choose, chooseInt)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Pixel (RGB(..))
import Puregrain.Quantize (evenRamp, nearestLevel, perChannel, quantizeWith, runQuantize, threshold)
import Test.Puregrain.Arbitrary (TestImage(..), TestKernel(..), TestLevels(..), TestLevelsRGBImage(..), TestRGB(..), TestRGBImage(..), TestSample(..))
import Test.Puregrain.Util (approxEqual, dither, neutral, nonNeutralCount, runAtOrigin)

-- | An independent reference for `nearestLevel`, written as the
-- | specification itself rather than as another fold: "the FIRST level
-- | in `levels` whose distance to `x` equals the minimum distance".
-- | That makes the earlier-wins tie-break explicit. (Deliberately not
-- | `Data.Foldable.minimumBy`: it breaks exact ties toward the LATER
-- | element — `if cmp x y == LT then x else y` — the opposite rule.)
referenceNearestLevel :: NonEmptyArray Number -> Number -> Number
referenceNearestLevel levels x =
  case NEA.find (\l -> abs (x - l) == minDist) levels of
    Just l -> l
    Nothing -> x -- unreachable: minDist is attained by some level
  where
  minDist = NEA.foldl1 min (map (\l -> abs (x - l)) levels)

red :: RGB -> Number
red (RGB p) = p.r

green :: RGB -> Number
green (RGB p) = p.g

blue :: RGB -> Number
blue (RGB p) = p.b

-- | Projects one channel out of an RGB image, as a grayscale plane.
plane :: (RGB -> Number) -> Array (Array RGB) -> Array (Array Number)
plane channel = map (map channel)

spec :: Spec Unit
spec = describe "Puregrain.Quantize" do

  describe "Context (the pixel's position)" do
    -- What makes runAtOrigin (used throughout these tests) sound.
    it "position-blind quantizers give the same answer at every position" do
      quickCheck do
        x <- chooseInt 0 4096
        y <- chooseInt 0 4096
        v <- choose (-128.0) 383.0
        t <- choose 0.0 255.0
        TestLevels levels <- arbitrary
        let sameEverywhere q = runQuantize q { x, y } v == runAtOrigin q v
        pure (Array.all sameEverywhere [ threshold t, nearestLevel levels ] === true)

    -- A quantizer that ignores the value and returns its position as
    -- x + 1000·y, making the position it was given directly visible.
    it "perChannel hands every channel the same position" do
      let revealPosition = quantizeWith \c _ -> toNumber (c.x + 1000 * c.y)
      runQuantize (perChannel revealPosition) { x: 3, y: 5 } (RGB { r: 0.0, g: 0.0, b: 0.0 })
        `shouldEqual` RGB { r: 5003.0, g: 5003.0, b: 5003.0 }

  describe "perChannel" do
    it "on Number, is the scalar quantizer itself, unchanged" do
      quickCheck \(TestLevels levels) (TestSample x) ->
        let q = nearestLevel levels
        in runAtOrigin (perChannel q) x === runAtOrigin q x

    it "on RGB, applies the scalar quantizer to each channel independently" do
      quickCheck \(TestLevels levels) (TestRGB p@(RGB c)) ->
        let q = runAtOrigin (nearestLevel levels)
        in runAtOrigin (perChannel (nearestLevel levels)) p
             === RGB { r: q c.r, g: q c.g, b: q c.b }

    -- The claim the whole scalarED design rests on: because RGB's
    -- Ring/Scalable instances are component-wise, and a perChannel
    -- quantizer can't couple channels, dithering an RGB image once
    -- must give — channel for channel, exactly — what dithering each
    -- channel plane separately as grayscale gives.
    it "dithering RGB via perChannel == dithering each channel plane separately (scalarED equivalence)" do
      quickCheck \(TestKernel kernel) (TestLevels levels) (TestRGBImage image) ->
        let
          q = nearestLevel levels
          out = dither kernel (perChannel q) image
        in
          { r: plane red out, g: plane green out, b: plane blue out }
            ===
              { r: dither kernel q (plane red image)
              , g: dither kernel q (plane green image)
              , b: dither kernel q (plane blue image)
              }

    -- The exact checks from docs/test-images.md, stated for arbitrary
    -- input (npm run check:cli runs them end to end on the test images).
    -- Both also follow from the equivalence above; kept as direct
    -- statements of the documented claims.
    it "an image whose every channel value is a level comes back unchanged (zero error), for any levels and kernel" do
      quickCheck \(TestKernel kernel) (TestLevelsRGBImage { levels, image }) ->
        dither kernel (perChannel (nearestLevel levels)) image === image

    it "a neutral image stays exactly neutral, for any levels and kernel" do
      quickCheck \(TestKernel kernel) (TestLevels levels) (TestImage gray) ->
        nonNeutralCount (dither kernel (perChannel (nearestLevel levels)) (map (map neutral) gray)) === 0

  describe "nearestLevel" do
    it "agrees with an independent reference (first level at minimum distance)" do
      quickCheck \(TestLevels levels) (TestSample x) ->
        runAtOrigin (nearestLevel levels) x === referenceNearestLevel levels x

    it "always returns one of the given levels" do
      quickCheck \(TestLevels levels) (TestSample x) ->
        NEA.elem (runAtOrigin (nearestLevel levels) x) levels === true

    it "is total for out-of-range input: below the lowest level snaps to it, above the highest snaps to that" do
      quickCheck \(TestLevels levels) (TestSample x) ->
        let
          lo = NEA.foldl1 min levels
          hi = NEA.foldl1 max levels
          result = runAtOrigin (nearestLevel levels) x
        in
          if x <= lo then result === lo
          else if x >= hi then result === hi
          else true === true

    it "a single-level set maps every input to that level" do
      quickCheck \(TestSample x) ->
        runAtOrigin (nearestLevel (NEA.singleton 42.0)) x === 42.0

    it "an input exactly equal to a level maps to that level" do
      let q = runAtOrigin (nearestLevel (evenRamp 4))
      q 0.0 `shouldEqual` 0.0
      q 85.0 `shouldEqual` 85.0
      q 170.0 `shouldEqual` 170.0
      q 255.0 `shouldEqual` 255.0

    it "breaks an exact tie in favor of the earlier level" do
      runAtOrigin (nearestLevel (NEA.cons' 0.0 [ 255.0 ])) 127.5 `shouldEqual` 0.0
      runAtOrigin (nearestLevel (NEA.cons' 255.0 [ 0.0 ])) 127.5 `shouldEqual` 255.0

    it "does not depend on the order levels are given in (away from ties)" do
      quickCheck \(TestLevels levels) (TestSample x) ->
        runAtOrigin (nearestLevel (NEA.reverse levels)) x
          === runAtOrigin (nearestLevel levels) x

  describe "evenRamp" do
    it "matches hand-computed ramps" do
      NEA.toArray (evenRamp 2) `shouldEqual` [ 0.0, 255.0 ]
      NEA.toArray (evenRamp 4) `shouldEqual` [ 0.0, 85.0, 170.0, 255.0 ]
      NEA.toArray (evenRamp 6) `shouldEqual` [ 0.0, 51.0, 102.0, 153.0, 204.0, 255.0 ]

    it "n <= 1 (including zero and negative) collapses to a single midpoint level" do
      NEA.toArray (evenRamp 1) `shouldEqual` [ 127.5 ]
      NEA.toArray (evenRamp 0) `shouldEqual` [ 127.5 ]
      NEA.toArray (evenRamp (-3)) `shouldEqual` [ 127.5 ]

    it "for n >= 2: exactly n levels, from 0 to 255 inclusive, evenly spaced" do
      quickCheck do
        n <- chooseInt 2 64
        let
          ramp = evenRamp n
          levels = NEA.toArray ramp
          spacing = 255.0 / toNumber (n - 1)
          gaps = Array.zipWith (-) (Array.drop 1 levels) levels
        pure $
          { length: NEA.length ramp
          , first: NEA.head ramp
          , last: NEA.last ramp
          , evenlySpaced: Array.all (approxEqual spacing) gaps
          }
            ===
              { length: n, first: 0.0, last: 255.0, evenlySpaced: true }

  describe "threshold" do
    it "below the cut maps to 0, at or above it to 255" do
      let q = runAtOrigin (threshold 128.0)
      q 127.9 `shouldEqual` 0.0
      q 128.0 `shouldEqual` 255.0
      q 128.1 `shouldEqual` 255.0

    it "is total for out-of-range input" do
      let q = runAtOrigin (threshold 128.0)
      q (-50.0) `shouldEqual` 0.0
      q 400.0 `shouldEqual` 255.0

    it "only ever outputs 0 or 255, for any cut and any input" do
      quickCheck \(TestSample t) (TestSample x) ->
        let out = runAtOrigin (threshold t) x
        in (out == 0.0 || out == 255.0) === true

    -- The relationship its doc comment claims: threshold 127.5 and the
    -- 2-level ramp differ only exactly at the cut, where threshold says
    -- 255 (not below the cut) and nearestLevel breaks the tie toward the
    -- earlier level, 0.
    it "agrees with nearestLevel (evenRamp 2) everywhere except exactly at 127.5" do
      quickCheck \(TestSample x) ->
        if x == 127.5 then Success
        else runAtOrigin (threshold 127.5) x === runAtOrigin (nearestLevel (evenRamp 2)) x
      runAtOrigin (threshold 127.5) 127.5 `shouldEqual` 255.0
      runAtOrigin (nearestLevel (evenRamp 2)) 127.5 `shouldEqual` 0.0
