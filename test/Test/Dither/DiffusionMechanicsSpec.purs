module Test.Dither.DiffusionMechanicsSpec
  ( spec
  ) where

import Prelude

import Data.Array (mapWithIndex)
import Data.CatQueue (CatQueue)
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.List.Lazy as LL
import Data.List as DL
import Data.Tuple (Tuple(..))
import Test.QuickCheck (Result, (===))
import Test.Spec (Spec, describe, it)
import Test.Spec.QuickCheck (quickCheck)
import Type.Proxy (Proxy(..))

import Dither.Fifo (class Fifo)
import Dither.Image (ditherImageWith)
import Dither.Kernel (Kernel)
import Dither.Pixel (Quantize(..), quantize)
import Test.Dither.Arbitrary (TestKernel(..), TestImage(..))
import Test.Dither.Reference (referenceDither)

-- | A fixed, simple, position-blind quantizer. These properties check the
-- | DIFFUSION MECHANICS (padding, Fifo backend, DelayLine growth) against
-- | an independent reference — not the quantizer — so a simple one is
-- | enough.
testQuantize :: Quantize Number
testQuantize = quantize \x -> if x < 128.0 then 0.0 else 255.0

-- | A threshold that varies with the pixel's position. If a backend gave
-- | any pixel a wrong position, its output would differ from the
-- | reference's, so agreement proves the positions match pixel for pixel.
positionalThreshold :: Quantize Number
positionalThreshold = Quantize \c v -> if v < toNumber (32 + (37 * c.x + 61 * c.y) `mod` 192) then 0.0 else 255.0

-- | Ignores the value and returns the pixel's position as x + 1000·y, so
-- | the dithered image shows exactly which position each pixel was given.
revealPosition :: Quantize Number
revealPosition = Quantize \c _ -> toNumber (c.x + 1000 * c.y)

runWith
  :: forall f
   . Fifo f
  => Proxy f
  -> Kernel
  -> Quantize Number
  -> Array (Array Number)
  -> Array (Array Number)
runWith proxy kernel q image =
  LL.toUnfoldable (ditherImageWith proxy kernel q (LL.fromFoldable image))

agreesWithReference :: forall f. Fifo f => Proxy f -> Quantize Number -> TestKernel -> TestImage -> Result
agreesWithReference proxy q (TestKernel kernel) (TestImage image) =
  runWith proxy kernel q image === referenceDither kernel q image

spec :: Spec Unit
spec = describe "Dither.Image properties" do

  for_ [ Tuple "a position-blind threshold" testQuantize, Tuple "a position-dependent threshold" positionalThreshold ]
    \(Tuple label q) ->
      describe ("agrees with the independent reference implementation, with " <> label) do
        it "CatQueue backend" do
          quickCheck (agreesWithReference (Proxy :: Proxy CatQueue) q)
        it "List.Lazy backend" do
          quickCheck (agreesWithReference (Proxy :: Proxy LL.List) q)
        it "List backend" do
          quickCheck (agreesWithReference (Proxy :: Proxy DL.List) q)
        it "Array backend" do
          quickCheck (agreesWithReference (Proxy :: Proxy Array) q)

  describe "pixel positions" do
    it "each pixel's quantizer gets its own position: x from 0 in every row, y from 0 for the image" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        runWith (Proxy :: Proxy CatQueue) kernel revealPosition image
          === mapWithIndex (\y row -> mapWithIndex (\x _ -> toNumber (x + 1000 * y)) row) image
