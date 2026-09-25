module Test.Dither.Arbitrary where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Traversable (traverse)
import Dither.Kernel (Kernel, Offset)
import Dither.Pixel (RGB(..))
import Dither.Util (safeRange)
import Test.QuickCheck (class Arbitrary, arbitrary)
import Test.QuickCheck.Gen (Gen, chooseInt, choose, elements, vectorOf)

-- | Generates one Offset with dx in [dxLo, dxHi] and the given fixed dy.
genOffset :: Int -> Int -> Int -> Gen Offset
genOffset dxLo dxHi dy = do
  dx <- chooseInt dxLo dxHi
  weight <- choose 0.0 1.0
  pure { dx, dy, weight }

-- | Generates a structurally arbitrary Kernel: 0-3 "current" (dy=0)
-- | offsets with dx in [1,3], and, for each dy from 1 up to a random
-- | maxDy (0-3), 0-3 offsets with dx in [-3,3]. An empty kernel (no
-- | diffusion at all) is a valid, occasionally-generated edge case —
-- | deliberately not excluded.
genKernel :: Gen Kernel
genKernel = do
  numCurrent <- chooseInt 0 3
  currentOffsets <- vectorOf numCurrent (genOffset 1 3 0)
  maxDy <- chooseInt 0 3
  futureOffsets <- Array.concat <$> traverse genLayer (safeRange 1 maxDy)
  pure (currentOffsets <> futureOffsets)
  where
    genLayer :: Int -> Gen (Array Offset)
    genLayer dy = do
      n <- chooseInt 0 3
      vectorOf n (genOffset (-3) 3 dy)

newtype TestKernel = TestKernel Kernel

instance Arbitrary TestKernel where
  arbitrary = TestKernel <$> genKernel

-- | Generates a single arbitrary grayscale pixel row of the given
-- | width, pixel values in [0,255]. Factored out of genImage so a
-- | single-row generator (Step-level tests) and a many-same-width-rows
-- | generator (Row/Image-level tests) share one source of pixel values.
genRow :: Int -> Gen (Array Number)
genRow width = vectorOf width (choose 0.0 255.0)

-- | Generates a rectangular grayscale test image: width and height each
-- | in [1,6] (small, so property-test iteration stays fast), pixel
-- | values in [0,255].
genImage :: Gen (Array (Array Number))
genImage = do
  width <- chooseInt 1 6
  height <- chooseInt 1 6
  vectorOf height (genRow width)

newtype TestImage = TestImage (Array (Array Number))

instance Arbitrary TestImage where
  arbitrary = TestImage <$> genImage

-- | Generates a single arbitrary grayscale pixel row: width in [1,6]
-- | (same range as genImage), pixel values in [0,255].
newtype TestRow = TestRow (Array Number)

instance Arbitrary TestRow where
  arbitrary = TestRow <$> (chooseInt 1 6 >>= genRow)

-- | Generates one arbitrary RGB color, channels in [0,255] — same
-- | range convention as genImage's grayscale pixel values.
genRGB :: Gen RGB
genRGB = do
  r <- choose 0.0 255.0
  g <- choose 0.0 255.0
  b <- choose 0.0 255.0
  pure (RGB { r, g, b })

newtype TestRGB = TestRGB RGB

instance Arbitrary TestRGB where
  arbitrary = TestRGB <$> genRGB

-- | Generates a rectangular RGB test image: width and height each in
-- | [1,6], like genImage. Each pixel's three channels are independent
-- | draws, so projecting out one channel gives three independent
-- | grayscale planes of the same shape — what the scalarED-equivalence
-- | property in `Test.Dither.PixelSpec` compares against.
genRGBImage :: Gen (Array (Array RGB))
genRGBImage = do
  width <- chooseInt 1 6
  height <- chooseInt 1 6
  vectorOf height (vectorOf width genRGB)

newtype TestRGBImage = TestRGBImage (Array (Array RGB))

instance Arbitrary TestRGBImage where
  arbitrary = TestRGBImage <$> genRGBImage

-- | Generates a non-empty set of 1-8 quantization levels in [0,255],
-- | in arbitrary (not sorted) order — `nearestLevel` must not depend
-- | on the order it's given.
genLevels :: Gen (NonEmptyArray Number)
genLevels = do
  n <- chooseInt 0 7
  h <- choose 0.0 255.0
  t <- vectorOf n (choose 0.0 255.0)
  pure (NEA.cons' h t)

newtype TestLevels = TestLevels (NonEmptyArray Number)

instance Arbitrary TestLevels where
  arbitrary = TestLevels <$> genLevels

-- | Generates a single value to quantize, in [-128,383] — deliberately
-- | wider than [0,255]: accumulated diffusion error routinely pushes
-- | `corrected` outside a channel's nominal range, and a Quantize must
-- | be total over that too (see `Dither.Pixel.Quantize`).
newtype TestSample = TestSample Number

instance Arbitrary TestSample where
  arbitrary = TestSample <$> choose (-128.0) 383.0

-- | Generates a small non-empty palette of 1-8 random RGB colors
-- | (small, so property-test iteration stays fast — same rationale as
-- | genImage's [1,6] width/height).
genPalette :: Gen (NonEmptyArray RGB)
genPalette = do
  n <- chooseInt 0 7
  h <- genRGB
  t <- vectorOf n genRGB
  pure (NEA.cons' h t)

newtype TestPalette = TestPalette (NonEmptyArray RGB)

instance Arbitrary TestPalette where
  arbitrary = TestPalette <$> genPalette

-- | A random palette, plus a rectangular image (width and height in
-- | [1,6]) made only of that palette's colors — every pixel is already a
-- | palette color, so dithering it with that palette has zero error.
newtype TestPaletteImage = TestPaletteImage { palette :: NonEmptyArray RGB, image :: Array (Array RGB) }

instance Arbitrary TestPaletteImage where
  arbitrary = do
    palette <- genPalette
    width <- chooseInt 1 6
    height <- chooseInt 1 6
    image <- vectorOf height (vectorOf width (elements palette))
    pure (TestPaletteImage { palette, image })

-- | Random levels, plus a rectangular RGB image (width and height in
-- | [1,6]) whose every channel value is one of those levels — the
-- | scalarED counterpart of TestPaletteImage.
newtype TestLevelsRGBImage = TestLevelsRGBImage { levels :: NonEmptyArray Number, image :: Array (Array RGB) }

instance Arbitrary TestLevelsRGBImage where
  arbitrary = do
    levels <- genLevels
    width <- chooseInt 1 6
    height <- chooseInt 1 6
    let level = elements levels
    image <- vectorOf height (vectorOf width (RGB <$> ({ r: _, g: _, b: _ } <$> level <*> level <*> level)))
    pure (TestLevelsRGBImage { levels, image })