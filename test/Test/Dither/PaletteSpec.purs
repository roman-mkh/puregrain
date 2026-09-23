module Test.Dither.PaletteSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Foldable (minimumBy)
import Data.Maybe (Maybe(..), isJust, isNothing)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Dither.Palette (CompiledPalette(..), compilePalette, compilePaletteFromArray, distance2, nearestColorFast, websafe216)
import Dither.Pixel (RGB(..), nearestLevel, perChannel, runQuantize)
import Test.Dither.Arbitrary (TestPalette(..), TestRGB(..))

black :: RGB
black = RGB { r: 0.0, g: 0.0, b: 0.0 }

white :: RGB
white = RGB { r: 255.0, g: 255.0, b: 255.0 }

-- | An independent, naive reference: minimizes distance2 directly via
-- | Data.Foldable.minimumBy, without CompiledPalette/the paired-fold
-- | machinery in nearestColorFast. Used as a QuickCheck oracle for
-- | nearestColorFast — the same role Test.Dither.Reference plays for
-- | the Fifo backends.
naiveNearest :: NonEmptyArray RGB -> RGB -> RGB
naiveNearest palette pixel = case minimumBy (comparing (distance2 pixel)) palette of
  Just nearest -> nearest
  Nothing -> pixel -- unreachable: palette is a NonEmptyArray

spec :: Spec Unit
spec = describe "Dither.Palette" do

  describe "distance2" do
    it "is zero for identical colors" do
      distance2 black black `shouldEqual` 0.0

    it "is symmetric" do
      distance2 black white `shouldEqual` distance2 white black

    it "matches a hand-computed value (3-4-5 triangle)" do
      distance2 (RGB { r: 0.0, g: 0.0, b: 0.0 }) (RGB { r: 3.0, g: 4.0, b: 0.0 })
        `shouldEqual` 25.0

  describe "compilePaletteFromArray" do
    it "fails on an empty array" do
      isNothing (compilePaletteFromArray distance2 []) `shouldEqual` true

    it "succeeds on a non-empty array, preserving the given colors" do
      isJust (compilePaletteFromArray distance2 [ black, white ]) `shouldEqual` true
      case compilePaletteFromArray distance2 [ black, white ] of
        Nothing -> fail "expected Just, got Nothing"
        Just (CompiledPalette p) -> NEA.toArray p.colors `shouldEqual` [ black, white ]

  describe "nearestColorFast" do
    it "returns the single color of a one-color palette, regardless of pixel" do
      quickCheck \(TestRGB pixel) ->
        nearestColorFast (compilePalette distance2 (NEA.singleton black)) pixel === black

    it "returns a palette entry unchanged when the pixel exactly matches it" do
      let palette = NEA.cons black (NEA.singleton white)
      nearestColorFast (compilePalette distance2 palette) black `shouldEqual` black
      nearestColorFast (compilePalette distance2 palette) white `shouldEqual` white

    it "breaks an exact tie in favor of the earlier palette entry" do
      let
        -- equidistant from black and white
        grayish = RGB { r: 127.5, g: 127.5, b: 127.5 }
        paletteBW = NEA.cons black (NEA.singleton white)
        paletteWB = NEA.cons white (NEA.singleton black)
      nearestColorFast (compilePalette distance2 paletteBW) grayish `shouldEqual` black
      nearestColorFast (compilePalette distance2 paletteWB) grayish `shouldEqual` white

    it "always returns a color that is actually in the palette" do
      quickCheck \(TestRGB pixel) (TestPalette palette) ->
        NEA.elem (nearestColorFast (compilePalette distance2 palette) pixel) palette === true

    it "agrees with an independent, naive minimumBy reference" do
      quickCheck \(TestRGB pixel) (TestPalette palette) ->
        nearestColorFast (compilePalette distance2 palette) pixel
          === naiveNearest palette pixel

  describe "websafe216" do
    let
      steps = [ 0.0, 51.0, 102.0, 153.0, 204.0, 255.0 ]
      colors = NEA.toArray websafe216

    it "has exactly 216 colors" do
      NEA.length websafe216 `shouldEqual` 216

    it "has no duplicates" do
      Array.length (Array.nubEq colors) `shouldEqual` 216

    it "uses only the six web-safe channel values, in every channel" do
      let onStep x = Array.elem x steps
      Array.all (\(RGB c) -> onStep c.r && onStep c.g && onStep c.b) colors `shouldEqual` true

    it "starts at black and ends at white (r slowest, b fastest)" do
      NEA.head websafe216 `shouldEqual` black
      NEA.last websafe216 `shouldEqual` white
      NEA.index websafe216 1 `shouldEqual` Just (RGB { r: 0.0, g: 0.0, b: 51.0 })
      NEA.index websafe216 6 `shouldEqual` Just (RGB { r: 0.0, g: 51.0, b: 0.0 })
      NEA.index websafe216 36 `shouldEqual` Just (RGB { r: 51.0, g: 0.0, b: 0.0 })

    -- vectorED and scalarED agree here, and not by accident: web-safe
    -- is a full Cartesian product of per-channel steps, and squared
    -- Euclidean distance is a sum of independent per-channel terms, so
    -- the nearest cube color is exactly the nearest step in each
    -- channel separately. Exact ties agree too: the cube's r-g-b order
    -- makes "earliest tied entry" mean "lower step in every tied
    -- channel", which is also `nearestLevel`'s earlier-wins pick on
    -- ascending steps. (Float addition is monotonic, so rounding can
    -- only turn a strict difference into a tie, never reverse it — the
    -- only possible disagreement needs a random channel value within
    -- ~1e-13 of a midpoint between steps; not a practical concern.)
    it "nearest color (vectorED) == perChannel nearest step (scalarED), for any pixel" do
      let
        vectorED = nearestColorFast (compilePalette distance2 websafe216)
        scalarED = runQuantize (perChannel (nearestLevel (NEA.cons' 0.0 (Array.drop 1 steps))))
      quickCheck \(TestRGB pixel) ->
        vectorED pixel === scalarED pixel
