module Test.Puregrain.PaletteSpec (spec) where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Foldable (minimumBy)
import Data.Maybe (Maybe(..), isJust, isNothing)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Palette (compilePalette, compilePaletteFromArray, distance2, nearestColor, nearestColorFast, paletteColors)
import Puregrain.Palette.Presets (websafe216)
import Puregrain.Pixel (RGB(..))
import Puregrain.Quantize (nearestLevel, perChannel)
import Test.Puregrain.Arbitrary (TestImage(..), TestKernel(..), TestPalette(..), TestPaletteImage(..), TestRGB(..), TestRGBImage(..))
import Test.Puregrain.Util (dither, neutral, nonNeutralCount, websafeSteps)

black :: RGB
black = RGB { r: 0.0, g: 0.0, b: 0.0 }

white :: RGB
white = RGB { r: 255.0, g: 255.0, b: 255.0 }

-- | An independent, naive reference: minimizes distance2 directly via
-- | Data.Foldable.minimumBy, without CompiledPalette/the paired-fold
-- | machinery in nearestColorFast. Used as a QuickCheck oracle for
-- | nearestColorFast — the same role Test.Puregrain.Reference plays for
-- | the Fifo backends.
naiveNearest :: NonEmptyArray RGB -> RGB -> RGB
naiveNearest palette pixel = case minimumBy (comparing (distance2 pixel)) palette of
  Just nearest -> nearest
  Nothing -> pixel -- unreachable: palette is a NonEmptyArray

spec :: Spec Unit
spec = describe "Puregrain.Palette" do

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
        Just p -> NEA.toArray (paletteColors p) `shouldEqual` [ black, white ]

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

  -- The exact checks from docs/test-images.md, stated for arbitrary
  -- kernels, palettes and images (npm run check:cli runs them end to end
  -- through the CLI on the generated test images).
  describe "whole images" do
    -- Follows from the per-pixel equivalence above by induction (same
    -- quantized pixel -> same error -> same next corrected value); kept as
    -- a direct statement of the documented byte-identity claim.
    it "websafe216 (vectorED) == 6 levels per channel (scalarED), for any kernel and image" do
      quickCheck \(TestKernel kernel) (TestRGBImage image) ->
        dither kernel (nearestColor websafe216) image
          === dither kernel (perChannel (nearestLevel websafeSteps)) image

    it "an image made only of palette colors dithers to itself (zero error), for any palette and kernel" do
      quickCheck \(TestKernel kernel) (TestPaletteImage { palette, image }) ->
        dither kernel (nearestColor palette) image === image

    it "a neutral image stays exactly neutral under websafe216, for any kernel" do
      quickCheck \(TestKernel kernel) (TestImage gray) ->
        nonNeutralCount (dither kernel (nearestColor websafe216) (map (map neutral) gray)) === 0
