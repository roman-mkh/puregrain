module Test.Puregrain.Cli.PipelineSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.Ord (abs)
import Dither.Kernel (atkinson, floydSteinberg, jarvisJudiceNinke)
import Dither.Palette (nearestColor)
import Dither.Palette.Presets (ansi16, ansi256, blackWhite, c64, cga16, websafe216, zxSpectrum)
import Dither.Pixel (Context, Quantize, RGB(..), evenRamp, nearestLevel, perChannel, runQuantize, threshold)
import Effect.Aff (Aff)
import Puregrain.Cli.Options (KernelName(..), PaletteName(..), QuantizerChoice(..))
import Puregrain.Cli.Pipeline (Pipeline(..), isNeutral, kernelOf, luma, paletteOf, pipelineFor, toNeutral)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)

-- A Pipeline holds a function, which can't be compared directly; instead
-- the chosen quantizer and the expected one are run on the same probes —
-- values on, between and outside the levels involved, including the
-- out-of-range values diffusion produces.
grayProbes :: Array Number
grayProbes = [ -40.0, 0.0, 20.0, 42.5, 63.7, 85.0, 100.0, 127.4, 127.5, 128.0, 170.0, 200.1, 255.0, 300.0 ]

rgbProbes :: Array RGB
rgbProbes =
  [ RGB { r: 0.0, g: 0.0, b: 0.0 }
  , RGB { r: 255.0, g: 255.0, b: 255.0 }
  , RGB { r: 0.0, g: 255.0, b: 0.0 }
  , RGB { r: 128.0, g: 64.0, b: 200.0 }
  , RGB { r: 30.0, g: 220.0, b: 140.0 }
  , RGB { r: -20.0, g: 300.0, b: 127.5 }
  ]

-- | Where the probes are quantized. Every quantizer the CLI builds is
-- | position-blind (the library's PixelSpec checks that), so any position
-- | gives the same answer.
origin :: Context
origin = { x: 0, y: 0 }

shouldBeGray :: Pipeline -> Quantize Number -> Aff Unit
shouldBeGray pipeline expected = case pipeline of
  Gray q -> map (runQuantize q origin) grayProbes `shouldEqual` map (runQuantize expected origin) grayProbes
  Color _ -> fail "expected gray processing, got RGB"

shouldBeColor :: Pipeline -> Quantize RGB -> Aff Unit
shouldBeColor pipeline expected = case pipeline of
  Color q -> map (runQuantize q origin) rgbProbes `shouldEqual` map (runQuantize expected origin) rgbProbes
  Gray _ -> fail "expected RGB processing, got gray"

approx :: Number -> Number -> Boolean
approx expected actual = abs (actual - expected) < 1.0e-9

spec :: Spec Unit
spec = describe "Puregrain.Cli.Pipeline" do

  -- The table "How the output is chosen" in cli/README.md. The second
  -- argument is true for an all-neutral input, and after --gray.
  describe "pipelineFor (the README's routing table)" do
    it "--threshold: gray, 1-bit — for gray and for color input" do
      for_ [ true, false ] \grayImage ->
        pipelineFor (Threshold 100.0) grayImage `shouldBeGray` threshold 100.0

    it "--levels on gray input: gray, N levels" do
      pipelineFor (Levels 4) true `shouldBeGray` nearestLevel (evenRamp 4)

    it "--levels on color input: each channel on its own (scalarED), RGB" do
      pipelineFor (Levels 4) false `shouldBeColor` perChannel (nearestLevel (evenRamp 4))

    it "--palette: whole pixel (vectorED), RGB — for gray and for color input" do
      for_ [ true, false ] \grayImage -> do
        pipelineFor (Palette BlackWhite) grayImage `shouldBeColor` nearestColor blackWhite
        pipelineFor (Palette Websafe216) grayImage `shouldBeColor` nearestColor websafe216

  describe "names -> library values" do
    it "each kernel name maps to the library's kernel" do
      kernelOf FloydSteinberg `shouldEqual` floydSteinberg
      kernelOf Atkinson `shouldEqual` atkinson
      kernelOf JarvisJudiceNinke `shouldEqual` jarvisJudiceNinke

    it "each palette name maps to the library's palette" do
      paletteOf BlackWhite `shouldEqual` blackWhite
      paletteOf Websafe216 `shouldEqual` websafe216
      paletteOf Cga16 `shouldEqual` cga16
      paletteOf Ansi16 `shouldEqual` ansi16
      paletteOf Ansi256 `shouldEqual` ansi256
      paletteOf C64 `shouldEqual` c64
      paletteOf ZxSpectrum `shouldEqual` zxSpectrum

  describe "luma (gray conversion)" do
    -- Regression test: with the Rec. 601 weights applied to r = g = b = v,
    -- 65 of the 256 levels (128 among them) come out one float step low —
    -- which is how the old JS CLI converted every pixel.
    it "is exact for every neutral pixel, all 256 levels" do
      let levels = map toNumber (0 .. 255)
      map (\v -> luma (RGB { r: v, g: v, b: v })) levels `shouldEqual` levels

    it "is Rec. 601 luma (0.299 R + 0.587 G + 0.114 B) for colored pixels" do
      luma (RGB { r: 255.0, g: 0.0, b: 0.0 }) `shouldSatisfy` approx 76.245
      luma (RGB { r: 0.0, g: 255.0, b: 0.0 }) `shouldSatisfy` approx 149.685
      luma (RGB { r: 0.0, g: 0.0, b: 255.0 }) `shouldSatisfy` approx 29.07
      luma (RGB { r: 128.0, g: 64.0, b: 200.0 }) `shouldSatisfy` approx 98.64

    it "toNeutral gives a neutral pixel at the luma value" do
      let px = toNeutral (RGB { r: 128.0, g: 64.0, b: 200.0 })
      px `shouldSatisfy` isNeutral
      luma px `shouldSatisfy` approx 98.64
