module Test.Puregrain.Web.TextSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Settings (Colors(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Target(..), chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, initial)
import Puregrain.Web.Text (texts)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Text" do
  it "describes a result in the menus' words, in the settings' order" do
    texts.describe (initial { colors = Levels 4, kernel = Atkinson }) `shouldEqual` "4 levels, Atkinson"
    texts.describe (initial { colors = Threshold 128, kernel = FloydSteinberg }) `shouldEqual` "threshold 128, Floyd-Steinberg"
    texts.describe (chooseGray true (chooseKernel JarvisJudiceNinke (chooseColors (Palette Websafe216) initial)))
      `shouldEqual` "Web-safe, 216 colors, Jarvis-Judice-Ninke, gray first"
    texts.describe (chooseGray true (chooseBayer (Just 8) (chooseColors (Levels 2) initial)))
      `shouldEqual` "2 levels, ordered dithering 8×8, gray first"

  it "names a machine and its colors" do
    let zx = chooseTarget (Machine ZxSpectrumScreen) initial
    texts.describe (chooseBayer (Just 8) zx) `shouldEqual` "ZX Spectrum, 15 colors, normal and bright, ordered dithering 8×8"
    texts.describe (chooseKernel Atkinson (chooseColors (MachineColors BrightPalette) zx))
      `shouldEqual` "ZX Spectrum, 8 colors, bright only, Atkinson"
    texts.describe (chooseBayer (Just 4) (chooseTarget (Machine C64HiresScreen) initial))
      `shouldEqual` "Commodore 64, 16 colors, ordered dithering 4×4"

  it "says a run's time left first, its rows after it" do
    texts.dithering { done: 465, total: 1536, left: Just { minutes: 0, seconds: 10 } } `shouldEqual` "Dithering: about 10 s left (465/1536 rows)"
    texts.dithering { done: 1500, total: 1536, left: Just { minutes: 0, seconds: 0 } } `shouldEqual` "Dithering: a few seconds left (1500/1536 rows)"
    -- A run of a few seconds has no estimate (decision 23).
    texts.dithering { done: 465, total: 1536, left: Nothing } `shouldEqual` "Dithering: 465/1536 rows"

  it "names the pictures, and says when a result is done" do
    texts.originalNamed "plain.png" `shouldEqual` "The original: plain.png"
    texts.resultNamed (initial { colors = Levels 4, kernel = Atkinson }) `shouldEqual` "The result: 4 levels, Atkinson"
    texts.done (initial { colors = Levels 4, kernel = Atkinson }) `shouldEqual` "Done: 4 levels, Atkinson."
    texts.ditheringNow `shouldEqual` "Dithering…"
