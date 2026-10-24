module Test.Puregrain.Web.SettingsSpec (spec) where

import Prelude

import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Puregrain.Web.Settings (Colors(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Target(..), allKernels, allMachines, allPalettes, bayerSides, chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, flatCells, fromMessage, initial, isOriginal, machinePalettesOf, toMessage)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Settings" do
  describe "the rules, as in the CLI" do
    it "starts with every setting at none: the original" do
      isOriginal initial `shouldEqual` true
      initial `shouldEqual` { target: AnyScreen, colors: Original, kernel: NoDiffusion, bayer: Nothing, gray: false }

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
      chooseKernel Atkinson s `shouldEqual` { target: AnyScreen, colors: Levels 2, kernel: Atkinson, bayer: Just 8, gray: false }

  describe "a machine as the target" do
    let zx = chooseTarget (Machine ZxSpectrumScreen) initial

    it "starts with all the machine's colors, and any screen again with none" do
      zx.colors `shouldEqual` MachineColors FullPalette
      chooseTarget AnyScreen zx `shouldEqual` initial

    it "keeps the method across targets" do
      let s = chooseTarget (Machine C64HiresScreen) (chooseKernel Atkinson (chooseBayer (Just 4) (chooseColors (Levels 6) initial)))
      { kernel: s.kernel, bayer: s.bayer } `shouldEqual` { kernel: Atkinson, bayer: Just 4 }
      s.colors `shouldEqual` MachineColors FullPalette

    it "takes only the machine's own colors, and a machine's colors only with that machine" do
      chooseColors (Threshold 128) zx `shouldEqual` zx
      chooseColors (Palette Websafe216) zx `shouldEqual` zx
      (chooseColors (MachineColors BrightPalette) zx).colors `shouldEqual` MachineColors BrightPalette
      let c64 = chooseTarget (Machine C64HiresScreen) initial
      chooseColors (MachineColors NormalPalette) c64 `shouldEqual` c64
      chooseColors (MachineColors FullPalette) initial `shouldEqual` initial

    it "takes a Bayer map with the machine's colors: ordered dithering inside the cells" do
      (chooseBayer (Just 8) zx).bayer `shouldEqual` Just 8

    it "gives a method chosen without colors all the machine's colors" do
      let none = chooseColors Original zx
      isOriginal none `shouldEqual` true
      (chooseKernel FloydSteinberg none).colors `shouldEqual` MachineColors FullPalette
      (chooseBayer (Just 8) none).colors `shouldEqual` MachineColors FullPalette

    it "flags flat cells: a machine's colors with neither a kernel nor a Bayer map" do
      flatCells zx `shouldEqual` true
      flatCells (chooseKernel Atkinson zx) `shouldEqual` false
      flatCells (chooseBayer (Just 8) zx) `shouldEqual` false
      flatCells (chooseColors Original zx) `shouldEqual` false
      flatCells (chooseColors (Levels 4) initial) `shouldEqual` false

  describe "messages to the worker" do
    it "reads back every combination the page can send" do
      let
        everyColors = [ Original, Threshold 0, Threshold 128, Threshold 255, Levels 2, Levels 256 ] <> map Palette allPalettes
      for_ everyColors \colors -> for_ allKernels \kernel -> for_ ([ Nothing ] <> map Just bayerSides) \bayer -> for_ [ false, true ] \gray -> do
        let s = { target: AnyScreen, colors, kernel, bayer, gray }
        -- Combinations the rules rule out aren't sent; the rest come back.
        when (bayer == Nothing || colors == Original || isLevels colors) do
          fromMessage (toMessage s) `shouldEqual` Just s
      for_ allMachines \machine -> for_ ([ Original ] <> map MachineColors (machinePalettesOf machine)) \colors ->
        for_ allKernels \kernel -> for_ ([ Nothing ] <> map Just bayerSides) \bayer -> for_ [ false, true ] \gray -> do
          let s = { target: Machine machine, colors, kernel, bayer, gray }
          fromMessage (toMessage s) `shouldEqual` Just s

    it "rejects what the page wouldn't send" do
      let m = toMessage (chooseColors (Levels 4) initial)
      fromMessage (m { kernel = "sierra" }) `shouldEqual` Nothing
      fromMessage (m { colors = "nes" }) `shouldEqual` Nothing
      fromMessage (m { colors = "levels", amount = 1 }) `shouldEqual` Nothing
      fromMessage (m { colors = "threshold", amount = 256 }) `shouldEqual` Nothing
      fromMessage (m { bayer = 3 }) `shouldEqual` Nothing
      fromMessage (m { colors = "bw", bayer = 8 }) `shouldEqual` Nothing
      fromMessage (m { target = "msx" }) `shouldEqual` Nothing
      fromMessage (m { target = "zx-spectrum" }) `shouldEqual` Nothing
      fromMessage (m { colors = "full" }) `shouldEqual` Nothing
      fromMessage (m { target = "c64-hires", colors = "normal", amount = 0 }) `shouldEqual` Nothing
      fromMessage (m { target = "zx-spectrum", colors = "bright", amount = 0 }) `shouldEqual` Just ((chooseTarget (Machine ZxSpectrumScreen) initial) { colors = MachineColors BrightPalette })
  where
  isLevels = case _ of
    Levels _ -> true
    _ -> false
