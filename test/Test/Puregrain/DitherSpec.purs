module Test.Puregrain.DitherSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..))
import Data.Maybe (Maybe(..), maybe)
import Data.String (Pattern(..), contains)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Exception (message, try)
import Partial.Unsafe (unsafeCrashWith)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Dither (ditherImage, ditherRows)
import Puregrain.Kernel (floydSteinberg)
import Puregrain.Ordered (ordered)
import Puregrain.Quantize (Quantize, evenRamp, threshold)
import Test.Puregrain.Arbitrary (TestImage(..), TestKernel(..))
import Test.Puregrain.Util (bayerMap)

q :: Quantize Number
q = threshold 128.0

-- | Runs `f` when the effect runs, not when it's built. (A leading `let`
-- | in a `do` block would be evaluated while building the effect, and an
-- | error thrown there would escape `try`.)
whenRun :: forall a. (Unit -> a) -> Effect a
whenRun f = pure unit >>= \_ -> pure (f unit)

-- | The error the computation `f` stops with, if any. `f` runs inside
-- | `try`, which is where the error surfaces; `f` must force the result.
errorOf :: forall a. (Unit -> a) -> Effect (Maybe String)
errorOf f = do
  result <- try (whenRun f)
  pure case result of
    Left err -> Just (message err)
    Right _ -> Nothing

mentions :: String -> Maybe String -> Boolean
mentions text = maybe false (contains (Pattern text))

-- | All rows of the lazy result, which forces each of them.
allRows :: forall a. LL.List (Array a) -> Array (Array a)
allRows = LL.toUnfoldable

spec :: Spec Unit
spec = describe "Puregrain.Dither" do

  describe "ditherImage and ditherRows" do
    -- A position-dependent quantizer, so the two must also give every
    -- pixel the same position.
    it "give the same rows, for any kernel and image" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        let bayer = ordered (bayerMap 4) (evenRamp 3)
        in ditherImage kernel bayer image === allRows (ditherRows kernel bayer (LL.fromFoldable image))

  describe "ditherRows is lazy" do
    it "works on an endless stream of rows" do
      let row = [ 10.0, 200.0, 90.0, 130.0 ]
      allRows (LL.take 3 (ditherRows floydSteinberg q (LL.repeat row)))
        `shouldEqual` ditherImage floydSteinberg q [ row, row, row ]

    it "reads an input row only when its result row is asked for" do
      let
        first = [ 10.0, 200.0, 90.0 ]
        second = [ 30.0, 140.0, 250.0 ]
        -- An input whose third row stops with an error when it's read.
        input = LL.cons first (LL.cons second (List (defer \_ -> unsafeCrashWith "the third input row was read")))
        out = ditherRows floydSteinberg q input
      -- Two result rows read the first two input rows, not the third…
      allRows (LL.take 2 out) `shouldEqual` ditherImage floydSteinberg q [ first, second ]
      -- …and the third result row is what reads the third input row.
      result <- liftEffect (errorOf \_ -> LL.length (LL.take 3 out))
      result `shouldSatisfy` mentions "the third input row was read"

  describe "rows of different lengths (a caller's bug)" do
    let
      tooLong = [ [ 10.0, 200.0, 90.0 ], [ 30.0, 140.0, 250.0 ], [ 60.0, 70.0, 80.0, 90.0 ] ]
      tooShort = [ [ 10.0, 200.0, 90.0 ], [ 30.0, 140.0 ] ]

    it "ditherImage stops with an error naming the row, for a longer and a shorter row" do
      long <- liftEffect (errorOf \_ -> Array.length (ditherImage floydSteinberg q tooLong))
      long `shouldSatisfy` mentions "row 2 has 4 pixels, but the first row has 3"
      short <- liftEffect (errorOf \_ -> Array.length (ditherImage floydSteinberg q tooShort))
      short `shouldSatisfy` mentions "row 1 has 2 pixels, but the first row has 3"

    it "ditherRows stops when it reaches that row; the rows before it come out" do
      let out = ditherRows floydSteinberg q (LL.fromFoldable tooLong)
      allRows (LL.take 2 out) `shouldEqual` ditherImage floydSteinberg q (Array.take 2 tooLong)
      result <- liftEffect (errorOf \_ -> Array.length (allRows out))
      result `shouldSatisfy` mentions "row 2 has 4 pixels, but the first row has 3"

    it "an image whose rows all have the same length comes through" do
      result <- liftEffect (errorOf \_ -> Array.length (ditherImage floydSteinberg q [ [ 10.0, 200.0 ], [ 30.0, 140.0 ], [ 60.0, 70.0 ] ]))
      result `shouldEqual` Nothing
