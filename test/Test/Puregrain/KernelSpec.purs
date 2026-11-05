module Test.Puregrain.KernelSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_, sum)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), maybe)
import Data.Number (infinity, nan)
import Data.Ord (abs)
import Data.String (Pattern(..), contains)
import Data.Tuple (Tuple(..))
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Kernel (Kernel, Offset, atkinson, burkes, fan, floydSteinberg, fromOffsets, jarvisJudiceNinke, noDiffusion, offsets, shiauFan, shiauFan2, sierra2, sierra3, sierraLite, stucki)
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

-- | A kernel's table as published: its rows, from the current pixel's row
-- | down, the current pixel's column in them, and the divisor. Blanks, and
-- | the current pixel itself, are 0.
type Table = { rows :: Array (Array Int), x :: Int, divisor :: Int }

-- | A table's offsets in scan order, row by row, left to right, as the
-- | presets list them.
fromTable :: Table -> Array Offset
fromTable table = Array.filter (\o -> o.weight /= 0.0) do
  Tuple dy row <- Array.mapWithIndex Tuple table.rows
  Tuple column value <- Array.mapWithIndex Tuple row
  pure { dx: column - table.x, dy, weight: toNumber value / toNumber table.divisor }

-- | The kernels added in 0.2.1, each with its table as published (see
-- | docs/error-diffusion.md for the sources), written out here
-- | independently of the library's offsets.
published :: Array { name :: String, kernel :: Kernel, table :: Table }
published =
  [ { name: "Stucki", kernel: stucki, table: { x: 2, divisor: 42, rows: [ [ 0, 0, 0, 8, 4 ], [ 2, 4, 8, 4, 2 ], [ 1, 2, 4, 2, 1 ] ] } }
  , { name: "Burkes", kernel: burkes, table: { x: 2, divisor: 32, rows: [ [ 0, 0, 0, 8, 4 ], [ 2, 4, 8, 4, 2 ] ] } }
  , { name: "Sierra 3", kernel: sierra3, table: { x: 2, divisor: 32, rows: [ [ 0, 0, 0, 5, 3 ], [ 2, 4, 5, 4, 2 ], [ 0, 2, 3, 2, 0 ] ] } }
  , { name: "Sierra 2", kernel: sierra2, table: { x: 2, divisor: 16, rows: [ [ 0, 0, 0, 4, 3 ], [ 1, 2, 3, 2, 1 ] ] } }
  , { name: "Sierra Lite", kernel: sierraLite, table: { x: 1, divisor: 4, rows: [ [ 0, 0, 2 ], [ 1, 1, 0 ] ] } }
  , { name: "Fan", kernel: fan, table: { x: 2, divisor: 16, rows: [ [ 0, 0, 0, 7 ], [ 1, 3, 5, 0 ] ] } }
  , { name: "Shiau-Fan", kernel: shiauFan, table: { x: 2, divisor: 8, rows: [ [ 0, 0, 0, 4 ], [ 1, 1, 2, 0 ] ] } }
  , { name: "Shiau-Fan 2", kernel: shiauFan2, table: { x: 3, divisor: 16, rows: [ [ 0, 0, 0, 0, 8 ], [ 1, 1, 2, 4, 0 ] ] } }
  ]

spec :: Spec Unit
spec = describe "Puregrain.Kernel" do

  describe "fromOffsets" do
    it "accepts the ready-made kernels' offsets, giving the same kernels back" do
      for_ ([ floydSteinberg, atkinson, jarvisJudiceNinke, noDiffusion ] <> map _.kernel published) \k ->
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

  describe "the kernels added in 0.2.1" do
    for_ published \p ->
      it (p.name <> " has its published table's offsets and weights") do
        offsets p.kernel `shouldEqual` fromTable p.table

    it "pass on all the error: their weights add up to 1" do
      for_ published \p ->
        (abs (weightSum p.kernel - 1.0) < 1.0e-12) `shouldEqual` true

    it "have 12, 7, 10, 7, 3, 4, 4 and 5 neighbours" do
      map (Array.length <<< offsets <<< _.kernel) published `shouldEqual` [ 12, 7, 10, 7, 3, 4, 4, 5 ]
