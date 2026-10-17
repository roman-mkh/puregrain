module Test.Puregrain.C64Spec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Foldable (all, and, sum)
import Data.Int (toNumber)
import Data.Maybe (fromMaybe)
import Data.Traversable (traverse)
import Test.QuickCheck (class Arbitrary, (===))
import Test.QuickCheck.Gen (chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Cells (cellColors, ditherCells)
import Puregrain.Machine.C64 (HiresCell, background, foreground, hiresCells, hiresPalette, hiresScreen)
import Puregrain.Pixel (RGB(..))
import Test.Puregrain.Arbitrary (TestCellQuantizer(..), TestKernel(..))

-- | The 16 colors by code, written out independently of the preset:
-- | Pepto's values (pepto.de/projects/colorvic/2001/).
pepto :: Array RGB
pepto = map hex
  [ 0x000000, 0xFFFFFF, 0x68372B, 0x70A4B2, 0x6F3D86, 0x588D43, 0x352879, 0xB8C76F
  , 0x6F4F25, 0x433900, 0x9A6759, 0x444444, 0x6C6C6C, 0x9AD284, 0x6C5EB5, 0x959595
  ]
  where
  hex n = RGB { r: toNumber (n / 65536), g: toNumber ((n / 256) `mod` 256), b: toNumber (n `mod` 256) }

expectedColor :: Int -> RGB
expectedColor code = fromMaybe (RGB { r: -1.0, g: -1.0, b: -1.0 }) (Array.index pepto code)

luma :: RGB -> Number
luma (RGB p) = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b

-- | The squared distance between two colors, written out here.
distance :: RGB -> RGB -> Number
distance (RGB a) (RGB b) = sum (map (\d -> d * d) [ a.r - b.r, a.g - b.g, a.b - b.b ])

colorsOf :: HiresCell -> NonEmptyArray RGB
colorsOf = cellColors <<< hiresPalette

-- | Two cells look the same if their colors are the same set.
sameColors :: HiresCell -> HiresCell -> Boolean
sameColors a b = all (\c -> NEA.elem c (colorsOf b)) (colorsOf a) && all (\c -> NEA.elem c (colorsOf a)) (colorsOf b)

all136 :: Array HiresCell
all136 = NEA.toArray hiresCells

-- | A picture made only of valid hires cells: 1 to 3 cells each way, each
-- | cell a random hires cell, each pixel one of that cell's colors.
newtype HiresPicture = HiresPicture (Array (Array RGB))

instance Arbitrary HiresPicture where
  arbitrary = do
    columns <- chooseInt 1 3
    rows <- chooseInt 1 3
    cells <- vectorOf rows (vectorOf columns (elements hiresCells))
    HiresPicture <<< Array.concat <$> traverse pixelRows cells
    where
    -- The 8 pixel rows of one row of cells.
    pixelRows row = vectorOf 8 (Array.concat <$> traverse (\c -> vectorOf 8 (elements (colorsOf c))) row)

spec :: Spec Unit
spec = describe "Puregrain.Machine.C64" do

  describe "hiresCells" do
    it "has the 136 cell palettes hires mode can show, all looking different" do
      Array.length all136 `shouldEqual` 136
      Array.length (Array.nubByEq sameColors all136) `shouldEqual` 136

    it "lists the 16 single colors first, by code, then the pairs, nearest first" do
      let
        singles = Array.takeWhile (\c -> foreground c == background c) all136
        pairs = Array.drop (Array.length singles) all136
        spreads = map (\c -> distance (expectedColor (foreground c)) (expectedColor (background c))) pairs
      map foreground singles `shouldEqual` Array.range 0 15
      Array.filter (\c -> foreground c == background c) pairs `shouldEqual` []
      and (Array.zipWith (<=) spreads (Array.drop 1 spreads)) `shouldEqual` true

    it "puts the darker color, by luma, in the foreground" do
      Array.filter (\c -> luma (expectedColor (foreground c)) > luma (expectedColor (background c))) all136 `shouldEqual` []

    it "uses the C64's colors, Pepto's values, foreground first" do
      let
        expected c =
          if foreground c == background c then NEA.singleton (expectedColor (foreground c))
          else NEA.cons' (expectedColor (foreground c)) [ expectedColor (background c) ]
      Array.filter (\c -> colorsOf c /= expected c) all136 `shouldEqual` []

  describe "hiresScreen" do
    it "is 8x8 cells, with the hires cells in their order and their colors" do
      hiresScreen.size `shouldEqual` { width: 8, height: 8 }
      NEA.toArray hiresScreen.candidates `shouldEqual` all136
      map (cellColors <<< hiresScreen.palette) all136 `shouldEqual` map colorsOf all136

    -- Holds only because of the order: grey, for example, lies on the
    -- line from black to white, so a cell of black and grey fits black
    -- and white perfectly too; the nearer pair must come first, or the
    -- grey pixels would turn into black and white dots.
    it "leaves a picture made only of valid hires cells unchanged, with any kernel and rule" do
      quickCheck \(TestKernel kernel) (TestCellQuantizer rule) (HiresPicture picture) ->
        (ditherCells kernel rule hiresScreen picture).image === picture
