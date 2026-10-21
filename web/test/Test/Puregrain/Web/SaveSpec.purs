module Test.Puregrain.Web.SaveSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Save (fileName)
import Puregrain.Web.Settings (Colors(..), KernelName(..), PaletteName(..), initial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Save" do
  describe "fileName" do
    it "names the settings in the form's order, with the CLI's names" do
      fileName "photo.jpg" (initial { colors = Levels 4, kernel = Atkinson, bayer = Just 8, gray = true })
        `shouldEqual` "photo-levels4-atkinson-bayer8-gray.png"
      fileName "photo.jpg" (initial { colors = Palette Websafe216, kernel = JarvisJudiceNinke })
        `shouldEqual` "photo-websafe216-jjn.png"
      fileName "photo.jpg" (initial { colors = Palette ZxSpectrum, kernel = FloydSteinberg })
        `shouldEqual` "photo-zx15-floyd-steinberg.png"

    it "leaves out the settings at none" do
      fileName "photo.jpg" (initial { colors = Threshold 128 }) `shouldEqual` "photo-threshold128.png"
      fileName "photo.jpg" (initial { colors = Levels 2, bayer = Just 4 }) `shouldEqual` "photo-levels2-bayer4.png"

    it "says 'original' for colors at none, though there's nothing to save then" do
      fileName "photo.jpg" initial `shouldEqual` "photo-original.png"

    it "drops only the last extension, and none from a name that starts with its only dot" do
      let settings = initial { colors = Threshold 128 }
      fileName "my.holiday.photo.png" settings `shouldEqual` "my.holiday.photo-threshold128.png"
      fileName "photo" settings `shouldEqual` "photo-threshold128.png"
      fileName ".png" settings `shouldEqual` ".png-threshold128.png"
