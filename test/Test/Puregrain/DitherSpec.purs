module Test.Puregrain.DitherSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..), maybe)
import Data.String (Pattern(..), contains)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Exception (message, try)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

import Puregrain.Dither (ditherImage)
import Puregrain.Kernel (floydSteinberg)
import Puregrain.Quantize (Quantize, threshold)
import Test.Puregrain.Util (dither)

q :: Quantize Number
q = threshold 128.0

-- | Runs `f` when the effect runs, not when it's built. (A leading `let`
-- | in a `do` block would be evaluated while building the effect, and an
-- | error thrown there would escape `try`.)
whenRun :: forall a. (Unit -> a) -> Effect a
whenRun f = pure unit >>= \_ -> pure (f unit)

-- | The error `ditherImage` stops with on this image, if any. The whole
-- | result is forced inside `try`, which is where the error surfaces.
errorOf :: Array (Array Number) -> Effect (Maybe String)
errorOf image = do
  result <- try (whenRun \_ -> Array.length (dither floydSteinberg q image))
  pure case result of
    Left err -> Just (message err)
    Right _ -> Nothing

mentions :: String -> Maybe String -> Boolean
mentions text = maybe false (contains (Pattern text))

spec :: Spec Unit
spec = describe "Puregrain.Dither" do

  describe "rows of different lengths (a caller's bug)" do
    it "a longer row stops with an error naming the row" do
      result <- liftEffect (errorOf [ [ 10.0, 200.0, 90.0 ], [ 30.0, 140.0, 250.0 ], [ 60.0, 70.0, 80.0, 90.0 ] ])
      result `shouldSatisfy` mentions "row 2 has 4 pixels, but the first row has 3"

    it "a shorter row too" do
      result <- liftEffect (errorOf [ [ 10.0, 200.0, 90.0 ], [ 30.0, 140.0 ] ])
      result `shouldSatisfy` mentions "row 1 has 2 pixels, but the first row has 3"

    it "the rows before it still come out: each row is checked when it's reached" do
      let
        good = [ [ 10.0, 200.0, 90.0 ], [ 30.0, 140.0, 250.0 ] ]
        firstTwo = LL.toUnfoldable (LL.take 2 (ditherImage floydSteinberg q (LL.fromFoldable (good <> [ [ 1.0 ] ]))))
      firstTwo `shouldEqual` dither floydSteinberg q good

    it "an image whose rows all have the same length comes through" do
      result <- liftEffect (errorOf [ [ 10.0, 200.0 ], [ 30.0, 140.0 ], [ 60.0, 70.0 ] ])
      result `shouldEqual` Nothing
