module Test.Puregrain.Web.ZoomSpec (spec) where

import Prelude

import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.Ord (abs)
import Puregrain.Web.Zoom (cssSize, zooms)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Zoom" do
  it "offers 1x to 4x" do
    zooms `shouldEqual` [ 1, 2, 3, 4 ]

  it "gives each picture pixel exactly zoom x zoom screen pixels, at any pixel ratio" do
    for_ [ 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0 ] \ratio -> for_ zooms \zoom -> do
      let size = cssSize ratio zoom { width: 320, height: 200 }
      -- CSS pixels times the ratio are screen pixels.
      (abs (size.width * ratio - toNumber (320 * zoom)) < 1.0e-9) `shouldEqual` true
      (abs (size.height * ratio - toNumber (200 * zoom)) < 1.0e-9) `shouldEqual` true

  it "is the picture's size times the zoom, with one screen pixel per CSS pixel" do
    cssSize 1.0 3 { width: 320, height: 200 } `shouldEqual` { width: 960.0, height: 600.0 }

  it "is half that with two screen pixels per CSS pixel, as on a high-density screen" do
    cssSize 2.0 1 { width: 320, height: 200 } `shouldEqual` { width: 160.0, height: 100.0 }
