module Test.Dither.DiffusionMechanicsSpec
  ( spec
  ) where

import Prelude

import Data.List.Lazy as LL
import Data.List as DL
import Data.Sequence (Seq)
import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.QuickCheck (quickCheck)
import Type.Proxy (Proxy(..))

import Dither.Fifo (class Fifo)
import Dither.Image (ditherImageWith)
import Dither.Kernel (Kernel)
import Dither.Pixel (Quantize(..))
import Test.Dither.Arbitrary (TestKernel(..), TestImage(..))
import Test.Dither.Reference (referenceDither)

-- | Fixed, simple quantizer shared by every property below. These
-- | properties check the DIFFUSION MECHANICS (padding, Fifo backend,
-- | DelayLine growth) against an independent reference and against
-- | each other — not `quantize` itself — so a single, simple quantizer
-- | is enough; which one is plugged in doesn't matter to what's being
-- | checked here.
testQuantize :: Quantize Number
testQuantize = Quantize \x -> if x < 128.0 then 0.0 else 255.0

runWith
  :: forall f
   . Fifo f
  => Proxy f
  -> Kernel
  -> Array (Array Number)
  -> Array (Array Number)
runWith proxy kernel image =
  LL.toUnfoldable (ditherImageWith proxy kernel testQuantize (LL.fromFoldable image))

spec :: Spec Unit
spec = describe "Dither.Image properties" do

  describe "agrees with the independent reference implementation" do
    it "Seq backend" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        runWith (Proxy :: Proxy Seq) kernel image === referenceDither kernel testQuantize image

    it "List.Lazy backend" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        runWith (Proxy :: Proxy LL.List) kernel image === referenceDither kernel testQuantize image

    it "List backend" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        runWith (Proxy :: Proxy DL.List) kernel image === referenceDither kernel testQuantize image

    it "Array backend" do
      quickCheck \(TestKernel kernel) (TestImage image) ->
        runWith (Proxy :: Proxy Array) kernel image === referenceDither kernel testQuantize image