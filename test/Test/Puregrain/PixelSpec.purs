module Test.Puregrain.PixelSpec (spec) where

import Prelude

import Test.QuickCheck ((===))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Pixel (RGB(..), RGBA(..), mapChannels)
import Test.Puregrain.Arbitrary (TestRGB(..))

spec :: Spec Unit
spec = describe "Puregrain.Pixel" do

  describe "mapChannels" do
    it "identity law: mapChannels identity == identity" do
      quickCheck \(TestRGB p) ->
        mapChannels identity p === p

    it "composition law: mapChannels (f <<< g) == mapChannels f <<< mapChannels g" do
      let
        f = (_ * 2.0)
        g = (_ + 1.0)
      quickCheck \(TestRGB p) ->
        mapChannels (f <<< g) p === (mapChannels f <<< mapChannels g) p

    it "RGB: applies the function to each channel independently" do
      mapChannels (_ * 10.0) (RGB { r: 1.0, g: 2.0, b: 3.0 })
        `shouldEqual` RGB { r: 10.0, g: 20.0, b: 30.0 }

    it "RGBA: applies the function to alpha too, like every other channel" do
      let RGBA result = mapChannels (_ * 10.0) (RGBA { r: 1.0, g: 2.0, b: 3.0, a: 4.0 })
      result `shouldEqual` { r: 10.0, g: 20.0, b: 30.0, a: 40.0 }

    it "Number: a single-channel pixel is its own only channel" do
      mapChannels (_ * 10.0) 4.0 `shouldEqual` 40.0
