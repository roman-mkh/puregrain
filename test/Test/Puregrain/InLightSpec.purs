module Test.Puregrain.InLightSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Either (Either(..))
import Data.Foldable (all, for_)
import Data.Int (toNumber)
import Data.List.Lazy as LL
import Data.Number (round)
import Test.QuickCheck ((<?>), (===))
import Test.QuickCheck.Gen (Gen, choose, chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Dither (Dithering, ditherImage, ditherImageWith, ditherRow, ditherRowsWith, initDitheringWith)
import Puregrain.Gamma (fromLight, gammaOff, gammaSrgb, toLight)
import Puregrain.Internal.Gamma (conversionFor)
import Puregrain.Internal.Quantize (quantizerFor)
import Puregrain.Kernel (floydSteinberg, noDiffusion)
import Puregrain.Ordered (ordered)
import Puregrain.Palette (nearestColor)
import Puregrain.Palette.Presets (websafe216)
import Puregrain.Pixel (RGB)
import Puregrain.Quantize (Quantize, evenRamp, nearestLevel, perChannel, quantizeWith, runQuantize, runQuantizeWith, threshold)
import Test.Puregrain.Arbitrary (genByte, genByteRGB, genImage, genKernel, genLevels, genPalette, genRGBImage)
import Test.Puregrain.Reference (referenceDitherResolved)
import Test.Puregrain.Util (bayerMap, curves)

-- | 1 to 8 levels, whole bytes, in any order, repeats allowed.
genByteLevels :: Gen (NonEmptyArray Number)
genByteLevels = NEA.cons' <$> genByte <*> (chooseInt 0 7 >>= \n -> vectorOf n genByte)

-- | 1 to 8 colors of whole bytes.
genBytePalette :: Gen (NonEmptyArray RGB)
genBytePalette = NEA.cons' <$> genByteRGB <*> (chooseInt 0 7 >>= \n -> vectorOf n genByteRGB)

-- | A rectangular image, width and height in [1,6], of the given values.
genImageOf :: forall a. Gen a -> Gen (Array (Array a))
genImageOf value = do
  width <- chooseInt 1 6
  height <- chooseInt 1 6
  vectorOf height (vectorOf width value)

-- | One of the gray quantizers: a threshold, the nearest level, ordered
-- | dithering, and a position-dependent cut built with `quantizeWith`.
genGrayQuantizer :: Gen (Quantize Number)
genGrayQuantizer = do
  levels <- genLevels
  t <- choose 0.0 255.0
  side <- elements (NEA.cons' 1 [ 2, 4, 8 ])
  elements (NEA.cons' (threshold t) [ nearestLevel levels, ordered (bayerMap side) levels, positional ])
  where
  positional = quantizeWith \c v -> if v < toNumber (32 + (37 * c.x + 61 * c.y) `mod` 192) then 0.0 else 255.0

-- | Every row through `ditherRow`, from the given start.
stepAll :: Dithering Number -> Array (Array Number) -> Array (Array Number)
stepAll start rows = (Array.foldl next { dithering: start, out: [] } rows).out
  where
  next acc row = case ditherRow acc.dithering row of
    Right r -> { dithering: r.next, out: Array.snoc acc.out r.row }
    Left _ -> acc

spec :: Spec Unit
spec = describe "Dithering in light (ditherImageWith and the presets)" do

  it "with gammaOff, gives the plain drivers' rows" do
    quickCheck do
      kernel <- genKernel
      image <- genImage
      q <- genGrayQuantizer
      pure (ditherImageWith gammaOff kernel q image === ditherImage kernel q image)
    quickCheck do
      kernel <- genKernel
      image <- genRGBImage
      palette <- genPalette
      levels <- genLevels
      q <- elements (NEA.cons' (nearestColor palette) [ perChannel (nearestLevel levels) ])
      pure (ditherImageWith gammaOff kernel q image === ditherImage kernel q image)

  for_ curves \c -> describe c.name do

    it "dithers as the independent reference does, on rows taken to light and back" do
      quickCheck do
        kernel <- genKernel
        image <- genImage
        q <- genGrayQuantizer
        let
          inLight = map (map (toLight c.gamma)) image
          expected = map (map (fromLight c.gamma)) (referenceDitherResolved kernel (quantizerFor (conversionFor c.gamma) q) inLight)
        pure (ditherImageWith c.gamma kernel q image === expected)

    it "gives the same rows through the stream and the stepper" do
      quickCheck do
        kernel <- genKernel
        image <- genImage
        q <- genGrayQuantizer
        let
          whole = ditherImageWith c.gamma kernel q image
          streamed = LL.toUnfoldable (ditherRowsWith c.gamma kernel q (LL.fromFoldable image))
          stepped = stepAll (initDitheringWith c.gamma kernel q) image
        pure ((streamed == whole && stepped == whole) <?> "the stream or the stepper differs")

    it "brings back a picture made only of its levels or colors, with any kernel" do
      quickCheck do
        kernel <- genKernel
        levels <- genByteLevels
        image <- genImageOf (elements levels)
        side <- elements (NEA.cons' 1 [ 2, 4, 8 ])
        q <- elements (NEA.cons' (nearestLevel levels) [ ordered (bayerMap side) levels ])
        pure (ditherImageWith c.gamma kernel q image === image)
      quickCheck do
        kernel <- genKernel
        palette <- genBytePalette
        image <- genImageOf (elements palette)
        pure (ditherImageWith c.gamma kernel (nearestColor palette) image === image)

    it "gives websafe216's results with perChannel (nearestLevel (evenRamp 6))" do
      quickCheck do
        kernel <- genKernel
        image <- genRGBImage
        pure
          ( ditherImageWith c.gamma kernel (nearestColor websafe216) image
              === ditherImageWith c.gamma kernel (perChannel (nearestLevel (evenRamp 6))) image
          )

    it "without diffusion, gives ditherImage's picture for threshold, nearestLevel and palettes" do
      quickCheck do
        image <- genImageOf genByte
        levels <- genByteLevels
        t <- genByte
        q <- elements (NEA.cons' (threshold t) [ nearestLevel levels ])
        pure (ditherImageWith c.gamma noDiffusion q image === ditherImage noDiffusion q image)
      quickCheck do
        image <- genImageOf genByteRGB
        palette <- genBytePalette
        pure (ditherImageWith c.gamma noDiffusion (nearestColor palette) image === ditherImage noDiffusion (nearestColor palette) image)

    it "outputs only its levels, rounded to whole numbers, and only the palette's colors" do
      quickCheck do
        kernel <- genKernel
        image <- genImage
        levels <- genLevels
        side <- elements (NEA.cons' 1 [ 2, 4, 8 ])
        q <- elements (NEA.cons' (nearestLevel levels) [ ordered (bayerMap side) levels ])
        let allowed = map round (NEA.toArray levels)
        pure (all (all (\v -> Array.elem v allowed)) (ditherImageWith c.gamma kernel q image) <?> "an output that isn't one of the rounded levels")
      quickCheck do
        kernel <- genKernel
        image <- genRGBImage
        palette <- genBytePalette
        pure (all (all (\v -> NEA.elem v palette)) (ditherImageWith c.gamma kernel (nearestColor palette) image) <?> "an output that isn't one of the palette's colors")

  describe "gammaSrgb" do
    it "gives a flat 128 about 21.6% white dots with Floyd-Steinberg" do
      let
        out = ditherImageWith gammaSrgb floydSteinberg (threshold 128.0) (Array.replicate 128 (Array.replicate 128 128.0))
        white = toNumber (Array.length (Array.filter (_ == 255.0) (Array.concat out))) / (128.0 * 128.0)
      white `shouldSatisfy` \w -> w > 0.212 && w < 0.220

    it "turns a flat 128 into 14 white dots of every 64 with the 8x8 Bayer map" do
      let out = ditherImageWith gammaSrgb noDiffusion (ordered (bayerMap 8) (evenRamp 2)) (Array.replicate 16 (Array.replicate 16 128.0))
      Array.length (Array.filter (_ == 255.0) (Array.concat out)) `shouldEqual` 56

  describe "runQuantizeWith" do
    it "with gammaOff, is runQuantize" do
      quickCheck do
        q <- genGrayQuantizer
        v <- choose (-128.0) 383.0
        x <- chooseInt 0 20
        y <- chooseInt 0 20
        pure (runQuantizeWith gammaOff q { x, y } v === runQuantize q { x, y } v)

    it "chooses the level nearest on stored values: gray 130 takes 170, not 85" do
      runQuantizeWith gammaSrgb (nearestLevel (evenRamp 4)) { x: 0, y: 0 } 130.0 `shouldEqual` 170.0
