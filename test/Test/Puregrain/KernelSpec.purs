module Test.Puregrain.KernelSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_, sum)
import Data.Maybe (Maybe(..), maybe)
import Data.Number (infinity, nan)
import Data.Ord (abs)
import Data.String (Pattern(..), contains)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Kernel (Kernel, atkinson, floydSteinberg, fromOffsets, jarvisJudiceNinke, noDiffusion, offsets)
import Test.Puregrain.Arbitrary (genOffsets)

-- | The error message of a rejected kernel, if any.
messageOf :: Either String Kernel -> Maybe String
messageOf = case _ of
  Left message -> Just message
  Right _ -> Nothing

mentions :: String -> Maybe String -> Boolean
mentions text = maybe false (contains (Pattern text))

weightSum :: Kernel -> Number
weightSum = sum <<< map _.weight <<< offsets

spec :: Spec Unit
spec = describe "Puregrain.Kernel" do

  describe "fromOffsets" do
    it "accepts the ready-made kernels' offsets, giving the same kernels back" do
      for_ [ floydSteinberg, atkinson, jarvisJudiceNinke, noDiffusion ] \k ->
        fromOffsets (offsets k) `shouldEqual` Right k

    it "accepts the empty list: that's noDiffusion" do
      fromOffsets [] `shouldEqual` Right noDiffusion

    it "accepts every generated kernel, and gives its offsets back unchanged" do
      quickCheck do
        list <- genOffsets
        pure ((offsets <$> fromOffsets list) === Right list)

    it "rejects an offset that doesn't point forward, saying which" do
      for_ [ { dx: 0, dy: 0 }, { dx: -1, dy: 0 }, { dx: -3, dy: 0 }, { dx: 0, dy: -1 }, { dx: 2, dy: -1 } ] \{ dx, dy } ->
        messageOf (fromOffsets [ { dx: 1, dy: 0, weight: 0.5 }, { dx, dy, weight: 0.5 } ])
          `shouldSatisfy` mentions ("offset 1 (dx " <> show dx <> ", dy " <> show dy <> ") doesn't point forward")

    it "rejects a weight that isn't a finite number" do
      for_ [ nan, infinity, -infinity ] \w ->
        messageOf (fromOffsets [ { dx: 1, dy: 0, weight: w } ])
          `shouldSatisfy` mentions ("offset 0 (dx 1, dy 0) has the weight " <> show w)

    it "rejects two offsets to the same neighbour, naming both" do
      messageOf (fromOffsets [ { dx: 1, dy: 0, weight: 0.5 }, { dx: 0, dy: 1, weight: 0.25 }, { dx: 1, dy: 0, weight: 0.25 } ])
        `shouldSatisfy` mentions "offsets 0 and 2 both point to dx 1, dy 0"

  describe "the ready-made kernels" do
    it "Floyd-Steinberg and Jarvis-Judice-Ninke pass on all the error, Atkinson 3/4" do
      weightSum floydSteinberg `shouldEqual` 1.0
      weightSum atkinson `shouldEqual` 0.75
      (abs (weightSum jarvisJudiceNinke - 1.0) < 1.0e-12) `shouldEqual` true

    it "have 4, 6 and 12 neighbours; noDiffusion none" do
      map (Array.length <<< offsets) [ floydSteinberg, atkinson, jarvisJudiceNinke, noDiffusion ]
        `shouldEqual` [ 4, 6, 12, 0 ]
