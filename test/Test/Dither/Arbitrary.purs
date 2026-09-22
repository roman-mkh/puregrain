module Test.Dither.Arbitrary where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Traversable (traverse)
import Dither.Kernel (Kernel, Offset)
import Dither.Util (safeRange)
import Test.QuickCheck (class Arbitrary, arbitrary)
import Test.QuickCheck.Gen (Gen, chooseInt, choose, vectorOf)

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

-- | Generates a rectangular grayscale test image: width and height each
-- | in [1,6] (small, so property-test iteration stays fast), pixel
-- | values in [0,255].
genImage :: Gen (Array (Array Number))
genImage = do
  width <- chooseInt 1 6
  height <- chooseInt 1 6
  vectorOf height (vectorOf width (choose 0.0 255.0))

newtype TestImage = TestImage (Array (Array Number))

instance Arbitrary TestImage where
  arbitrary = TestImage <$> genImage