module Test.Puregrain.Web.DownloadSpec (spec) where

import Prelude

import Puregrain.Web.Download (Format(..), buttonFormat, extension, formatsFor)
import Puregrain.Web.Settings (MachineName(..), Target(..))
import Puregrain.Web.Text (texts)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Download" do
  let
    zx = Machine ZxSpectrumScreen
    c64 = Machine C64HiresScreen

  it "offers a PNG only for any screen" do
    formatsFor AnyScreen { width: 320, height: 200 } `shouldEqual` [ { format: Png, possible: true } ]

  it "offers a machine's own files after the PNG, possible at its screen's size only" do
    formatsFor zx { width: 256, height: 192 } `shouldEqual`
      [ { format: Png, possible: true }, { format: Scr, possible: true }, { format: Tap, possible: true } ]
    formatsFor zx { width: 512, height: 512 } `shouldEqual`
      [ { format: Png, possible: true }, { format: Scr, possible: false }, { format: Tap, possible: false } ]
    formatsFor c64 { width: 320, height: 200 } `shouldEqual`
      [ { format: Png, possible: true }, { format: Prg, possible: true }, { format: Art, possible: true } ]
    -- The Spectrum's screen size isn't the C64's.
    formatsFor c64 { width: 256, height: 192 } `shouldEqual`
      [ { format: Png, possible: true }, { format: Prg, possible: false }, { format: Art, possible: false } ]

  it "names the format chosen last on the button, while it's possible" do
    buttonFormat Tap (formatsFor zx { width: 256, height: 192 }) `shouldEqual` Tap
    buttonFormat Art (formatsFor c64 { width: 320, height: 200 }) `shouldEqual` Art
    buttonFormat Png (formatsFor zx { width: 256, height: 192 }) `shouldEqual` Png

  it "falls back to PNG when that format isn't possible, and comes back to it" do
    -- Any screen, a poster for the Spectrum, the other machine.
    buttonFormat Tap (formatsFor AnyScreen { width: 256, height: 192 }) `shouldEqual` Png
    buttonFormat Tap (formatsFor zx { width: 512, height: 512 }) `shouldEqual` Png
    buttonFormat Tap (formatsFor c64 { width: 320, height: 200 }) `shouldEqual` Png
    -- The choice is kept, not the fallback: back on the screen, TAP again.
    buttonFormat Tap (formatsFor zx { width: 256, height: 192 }) `shouldEqual` Tap

  it "uses the CLI's extensions, and names the format on the button in capitals" do
    map extension [ Png, Scr, Tap, Prg, Art ] `shouldEqual` [ "png", "scr", "tap", "prg", "art" ]
    map texts.downloadAs [ Png, Scr, Tap, Prg, Art ] `shouldEqual`
      [ "Download PNG", "Download SCR", "Download TAP", "Download PRG", "Download ART" ]
    texts.needsScreen { width: 256, height: 192 } `shouldEqual` "needs a 256 × 192 picture"
