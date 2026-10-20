module Test.Puregrain.Web.SettingsSpec (spec) where

import Prelude

import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Puregrain.Web.Settings (Colors(..), KernelName(..), PaletteName(..), allKernels, allPalettes, bayerSides, chooseBayer, chooseColors, chooseGray, chooseKernel, fromMessage, initial, isOriginal, toMessage)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Settings" do
  describe "the rules, as in the CLI" do
    it "starts with every setting at none: the original" do
      isOriginal initial `shouldEqual` true
      initial `shouldEqual` { colors: Original, kernel: NoDiffusion, bayer: Nothing, gray: false }

    it "gives a kernel chosen without colors the CLI's default colors, a gray threshold at 128" do
      (chooseKernel FloydSteinberg initial).colors `shouldEqual` Threshold 128

    it "gives a Bayer map chosen without colors 2 levels, like the CLI's --bayer alone" do
      chooseBayer (Just 8) initial `shouldEqual` initial { colors = Levels 2, bayer = Just 8 }

    it "doesn't choose colors for 'no Bayer map', or for turning gray, which aren't methods" do
      isOriginal (chooseBayer Nothing initial) `shouldEqual` true
      isOriginal (chooseGray true initial) `shouldEqual` true

    it "keeps a Bayer map with levels, and turns it off with a threshold or a palette" do
      let ordered = chooseBayer (Just 4) (chooseColors (Levels 6) initial)
      (chooseColors (Levels 3) ordered).bayer `shouldEqual` Just 4
      (chooseColors (Threshold 100) ordered).bayer `shouldEqual` Nothing
      (chooseColors (Palette Websafe216) ordered).bayer `shouldEqual` Nothing

    it "ignores a Bayer map with a threshold or a palette, which the page doesn't offer it with" do
      for_ [ Threshold 128, Palette C64 ] \colors -> do
        let s = chooseColors colors initial
        chooseBayer (Just 8) s `shouldEqual` s

    it "keeps a Bayer map through 'none', and then gives a kernel 2 levels, not a threshold" do
      let s = chooseColors Original (chooseBayer (Just 8) (chooseColors (Levels 4) initial))
      isOriginal s `shouldEqual` true
      chooseKernel Atkinson s `shouldEqual` { colors: Levels 2, kernel: Atkinson, bayer: Just 8, gray: false }

  describe "messages to the worker" do
    it "reads back every combination the page can send" do
      let
        everyColors = [ Original, Threshold 0, Threshold 128, Threshold 255, Levels 2, Levels 256 ] <> map Palette allPalettes
      for_ everyColors \colors -> for_ allKernels \kernel -> for_ ([ Nothing ] <> map Just bayerSides) \bayer -> for_ [ false, true ] \gray -> do
        let s = { colors, kernel, bayer, gray }
        -- Combinations the rules rule out aren't sent; the rest come back.
        when (bayer == Nothing || colors == Original || isLevels colors) do
          fromMessage (toMessage s) `shouldEqual` Just s

    it "rejects what the page wouldn't send" do
      let m = toMessage (chooseColors (Levels 4) initial)
      fromMessage (m { kernel = "sierra" }) `shouldEqual` Nothing
      fromMessage (m { colors = "nes" }) `shouldEqual` Nothing
      fromMessage (m { colors = "levels", amount = 1 }) `shouldEqual` Nothing
      fromMessage (m { colors = "threshold", amount = 256 }) `shouldEqual` Nothing
      fromMessage (m { bayer = 3 }) `shouldEqual` Nothing
      fromMessage (m { colors = "bw", bayer = 8 }) `shouldEqual` Nothing
  where
  isLevels = case _ of
    Levels _ -> true
    _ -> false
