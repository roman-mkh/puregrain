module Test.Puregrain.Web.SettingsSpec (spec) where

import Prelude

import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Puregrain.Web.Settings (Colors(..), GammaName(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Target(..), allGammas, allKernels, allMachines, allPalettes, bayerSides, chooseBayer, chooseColors, chooseGamma, chooseGray, chooseKernel, chooseTarget, flatCells, fromMessage, gammaActs, gammaId, initial, isOriginal, kernelId, machinePalettesOf, toMessage)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Settings" do
  describe "the rules, as in the CLI" do
    it "starts with every setting at none: the original" do
      isOriginal initial `shouldEqual` true
      initial `shouldEqual` { target: AnyScreen, colors: Original, kernel: NoDiffusion, bayer: Nothing, gray: false, gamma: GammaOff }

    it "gives a kernel chosen without colors the CLI's default colors, a gray threshold at 128" do
      (chooseKernel FloydSteinberg initial).colors `shouldEqual` Threshold 128

    it "gives a Bayer map chosen without colors 2 levels, like the CLI's --bayer alone" do
      chooseBayer (Just 8) initial `shouldEqual` initial { colors = Levels 2, bayer = Just 8 }

    it "doesn't choose colors for 'no Bayer map', for turning gray, or for a gamma, which aren't methods" do
      isOriginal (chooseBayer Nothing initial) `shouldEqual` true
      isOriginal (chooseGray true initial) `shouldEqual` true
      isOriginal (chooseGamma GammaSrgb initial) `shouldEqual` true

    -- The two states the user compared (2026-11-15): after loading, and
    -- after a Bayer map chosen and set back to none, which keeps the 2
    -- levels it chose. In both, the gamma can't change the picture.
    it "says the gamma acts only with a method, gray first, or a picture mixed while it's prepared" do
      let
        afterLoad = initial
        afterBayerAndBack = chooseBayer Nothing (chooseBayer (Just 2) initial)
      afterBayerAndBack.colors `shouldEqual` Levels 2
      map (gammaActs false) [ afterLoad, afterBayerAndBack ] `shouldEqual` [ false, false ]
      gammaActs false (chooseGray true afterBayerAndBack) `shouldEqual` true
      gammaActs false (chooseKernel Atkinson afterBayerAndBack) `shouldEqual` true
      gammaActs false (chooseBayer (Just 4) afterBayerAndBack) `shouldEqual` true
      -- Without colors nothing is dithered, a kernel or gray first or not.
      gammaActs false (chooseColors Original (chooseKernel FloydSteinberg initial)) `shouldEqual` false
      gammaActs false (chooseGray true afterLoad) `shouldEqual` false
      -- Put onto a background or fitted: mixed in the gamma's light.
      map (gammaActs true) [ afterLoad, afterBayerAndBack ] `shouldEqual` [ true, true ]
      -- A machine's flat cells: the nearer of each cell's colors.
      gammaActs false (chooseTarget (Machine ZxSpectrumScreen) initial) `shouldEqual` false

    it "takes any gamma with any settings, and changes nothing else" do
      let s = chooseKernel Atkinson (chooseBayer (Just 4) (chooseColors (Levels 4) initial))
      for_ allGammas \g -> chooseGamma g s `shouldEqual` s { gamma = g }
      for_ allGammas \g -> chooseGamma g (chooseTarget (Machine ZxSpectrumScreen) s) `shouldEqual` (chooseTarget (Machine ZxSpectrumScreen) s) { gamma = g }

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
      chooseKernel Atkinson s `shouldEqual` { target: AnyScreen, colors: Levels 2, kernel: Atkinson, bayer: Just 8, gray: false, gamma: GammaOff }

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
    -- The CLI's names, written out here: the web package doesn't depend on
    -- the CLI's. The menu shows the kernels in this order.
    it "names the kernels as the CLI does, in the CLI's order with none first" do
      map kernelId allKernels `shouldEqual`
        [ "none", "floyd-steinberg", "atkinson", "jjn", "stucki", "burkes", "sierra-3", "sierra-2", "sierra-lite", "fan", "shiau-fan", "shiau-fan-2" ]

    it "names the gammas as the CLI's --gamma does, off first" do
      map gammaId allGammas `shouldEqual` [ "off", "1.2", "1.5", "1.8", "srgb" ]

    it "reads back every combination the page can send" do
      let
        everyColors = [ Original, Threshold 0, Threshold 128, Threshold 255, Levels 2, Levels 256 ] <> map Palette allPalettes
      for_ everyColors \colors -> for_ allKernels \kernel -> for_ ([ Nothing ] <> map Just bayerSides) \bayer -> for_ [ false, true ] \gray -> for_ allGammas \gamma -> do
        let s = { target: AnyScreen, colors, kernel, bayer, gray, gamma }
        -- Combinations the rules rule out aren't sent; the rest come back.
        when (bayer == Nothing || colors == Original || isLevels colors) do
          fromMessage (toMessage s) `shouldEqual` Just s
      for_ allMachines \machine -> for_ ([ Original ] <> map MachineColors (machinePalettesOf machine)) \colors ->
        for_ allKernels \kernel -> for_ ([ Nothing ] <> map Just bayerSides) \bayer -> for_ [ false, true ] \gray -> for_ allGammas \gamma -> do
          let s = { target: Machine machine, colors, kernel, bayer, gray, gamma }
          fromMessage (toMessage s) `shouldEqual` Just s

    it "rejects what the page wouldn't send" do
      let m = toMessage (chooseColors (Levels 4) initial)
      fromMessage (m { kernel = "sierra" }) `shouldEqual` Nothing
      fromMessage (m { colors = "nes" }) `shouldEqual` Nothing
      fromMessage (m { colors = "levels", amount = 1 }) `shouldEqual` Nothing
      fromMessage (m { colors = "threshold", amount = 256 }) `shouldEqual` Nothing
      fromMessage (m { bayer = 3 }) `shouldEqual` Nothing
      -- The page sends the five names only; "1.0" and "1" are the CLI's.
      fromMessage (m { gamma = "2.2" }) `shouldEqual` Nothing
      fromMessage (m { gamma = "1.0" }) `shouldEqual` Nothing
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
