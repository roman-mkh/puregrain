module Test.Puregrain.Web.SaveSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Save (fileName, tapeName)
import Puregrain.Web.Settings (Colors(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Target(..), chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, initial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Save" do
  describe "fileName" do
    it "names the settings in the form's order, with the CLI's names" do
      fileName "photo.jpg" (initial { colors = Levels 4, kernel = Atkinson, bayer = Just 8, gray = true }) "png"
        `shouldEqual` "photo-levels4-atkinson-bayer8-gray.png"
      fileName "photo.jpg" (initial { colors = Palette Websafe216, kernel = JarvisJudiceNinke }) "png"
        `shouldEqual` "photo-websafe216-jjn.png"
      fileName "photo.jpg" (initial { colors = Palette ZxSpectrum, kernel = FloydSteinberg }) "png"
        `shouldEqual` "photo-zx15-floyd-steinberg.png"

    it "names a machine, its palette unless it's the full one, and the format's extension" do
      let zx = chooseTarget (Machine ZxSpectrumScreen) initial
      fileName "photo.jpg" (chooseBayer (Just 8) zx) "scr" `shouldEqual` "photo-zx-spectrum-bayer8.scr"
      fileName "photo.jpg" (chooseKernel Atkinson (chooseColors (MachineColors BrightPalette) zx)) "png"
        `shouldEqual` "photo-zx-spectrum-bright-atkinson.png"
      fileName "photo.jpg" (chooseGray true (chooseBayer (Just 8) (chooseTarget (Machine C64HiresScreen) initial))) "prg"
        `shouldEqual` "photo-c64-hires-bayer8-gray.prg"

    it "leaves out the settings at none" do
      fileName "photo.jpg" (initial { colors = Threshold 128 }) "png" `shouldEqual` "photo-threshold128.png"
      fileName "photo.jpg" (initial { colors = Levels 2, bayer = Just 4 }) "png" `shouldEqual` "photo-levels2-bayer4.png"

    it "says 'original' for colors at none, though there's nothing to save then" do
      fileName "photo.jpg" initial "png" `shouldEqual` "photo-original.png"

    it "drops only the last extension, and none from a name that starts with its only dot" do
      let settings = initial { colors = Threshold 128 }
      fileName "my.holiday.photo.png" settings "png" `shouldEqual` "my.holiday.photo-threshold128.png"
      fileName "photo" settings "png" `shouldEqual` "photo-threshold128.png"
      fileName ".png" settings "png" `shouldEqual` ".png-threshold128.png"

  describe "tapeName, by the CLI's rule" do
    it "is the picture's name without its extension, the first 10 characters" do
      tapeName "photo.jpg" `shouldEqual` "photo"
      tapeName "my holiday photos.png" `shouldEqual` "my holiday"
      tapeName "my.photo.png" `shouldEqual` "my.photo"

    it "keeps printable ASCII only, and falls back to puregrain when none is left" do
      tapeName "café au lait.png" `shouldEqual` "caf au lai"
      tapeName "Фото.png" `shouldEqual` "puregrain"
