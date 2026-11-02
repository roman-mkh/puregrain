module Test.Puregrain.Web.ThemeSpec (spec) where

import Prelude

import Puregrain.Web.Theme (Theme(..), fromSystem, themeName, toggled)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Theme" do
  it "starts from the system's setting, and the switch toggles between the two" do
    fromSystem true `shouldEqual` Dark
    fromSystem false `shouldEqual` Light
    toggled Dark `shouldEqual` Light
    toggled Light `shouldEqual` Dark

  it "names each theme as the stylesheet reads it" do
    themeName Dark `shouldEqual` "dark"
    themeName Light `shouldEqual` "light"
