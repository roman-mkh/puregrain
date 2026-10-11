module Test.Puregrain.ZxSpectrumSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Foldable (all, and)
import Data.Traversable (traverse)
import Test.QuickCheck (class Arbitrary, (===))
import Test.QuickCheck.Gen (chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Cells (cellColors, ditherCells)
import Puregrain.Machine.ZxSpectrum (Attribute, attributePalette, attributes, bright, cellSize, ink, paper)
import Puregrain.Palette (distance2)
import Puregrain.Pixel (RGB(..))
import Test.Puregrain.Arbitrary (TestKernel(..))

-- | A color code's color, from the code's bits (1 blue, 2 red, 4 green),
-- | written independently of the preset: 0xD8 normal, 0xFF bright.
expectedColor :: Boolean -> Int -> RGB
expectedColor isBright code = RGB { r: on 2, g: on 4, b: on 1 }
  where
  level = if isBright then 255.0 else 216.0
  on bit = if (code / bit) `mod` 2 == 1 then level else 0.0

colorsOf :: Attribute -> NonEmptyArray RGB
colorsOf = cellColors <<< attributePalette

-- | Two attributes look the same if their colors are the same set.
sameColors :: Attribute -> Attribute -> Boolean
sameColors a b = all (\c -> NEA.elem c (colorsOf b)) (colorsOf a) && all (\c -> NEA.elem c (colorsOf a)) (colorsOf b)

all71 :: Array Attribute
all71 = NEA.toArray attributes

-- | A picture made only of valid cells: 1 to 3 cells each way, each cell
-- | a random attribute, each pixel one of that attribute's colors.
newtype TestScreen = TestScreen (Array (Array RGB))

instance Arbitrary TestScreen where
  arbitrary = do
    columns <- chooseInt 1 3
    rows <- chooseInt 1 3
    cellRows <- vectorOf rows (vectorOf columns (elements attributes))
    TestScreen <<< Array.concat <$> traverse pixelRows cellRows
    where
    -- The 8 pixel rows of one row of cells.
    pixelRows cells = vectorOf 8 (Array.concat <$> traverse (\a -> vectorOf 8 (elements (colorsOf a))) cells)

spec :: Spec Unit
spec = describe "Puregrain.Machine.ZxSpectrum" do

  describe "attributes" do
    it "has the 71 cell palettes the Spectrum can show, all looking different" do
      Array.length all71 `shouldEqual` 71
      Array.length (Array.nubByEq sameColors all71) `shouldEqual` 71

    it "follows the Spectrum's convention: ink the darker color, and all black without BRIGHT" do
      Array.filter (\a -> ink a > paper a) all71 `shouldEqual` []
      Array.filter (\a -> bright a && ink a == 0 && paper a == 0) all71 `shouldEqual` []

    it "lists the 15 single colors first, then the pairs, nearest first" do
      let
        singles = Array.takeWhile (\a -> ink a == paper a) all71
        pairs = Array.drop (Array.length singles) all71
        spread a = distance2 (expectedColor (bright a) (ink a)) (expectedColor (bright a) (paper a))
        spreads = map spread pairs
      Array.length singles `shouldEqual` 15
      Array.filter (\a -> ink a == paper a) pairs `shouldEqual` []
      and (Array.zipWith (<=) spreads (Array.drop 1 spreads)) `shouldEqual` true

    it "uses the Spectrum's colors, 0xD8 at normal brightness and 0xFF with BRIGHT" do
      let
        expected a =
          if ink a == paper a then NEA.singleton (expectedColor (bright a) (ink a))
          else NEA.cons' (expectedColor (bright a) (ink a)) [ expectedColor (bright a) (paper a) ]
      Array.filter (\a -> colorsOf a /= expected a) all71 `shouldEqual` []

  describe "dithering with the attributes" do
    -- Holds only because of the order: normal white, for example, lies on
    -- the segment from black to bright white, so a cell of black and
    -- normal white scores 0 with both pairs; the nearer pair must come
    -- first, or the white pixels would turn bright.
    it "leaves a picture made only of valid cells unchanged, with any kernel" do
      quickCheck \(TestKernel kernel) (TestScreen picture) ->
        (ditherCells kernel cellSize attributePalette attributes picture).image === picture
