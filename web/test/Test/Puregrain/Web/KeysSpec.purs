module Test.Puregrain.Web.KeysSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Keys (Shortcut(..), shortcut, zoomStep)
import Puregrain.Web.Text (texts)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Keys" do
  let
    plain key code = { key, code, ctrl: false, meta: false, alt: false, shift: false }
    ctrl key code = (plain key code) { ctrl = true }
    cmd key code = (plain key code) { meta = true }

  it "takes Ctrl+O and Ctrl+S, and Cmd for Ctrl, on every system" do
    shortcut (ctrl "o" "KeyO") `shouldEqual` Just ChoosePicture
    shortcut (ctrl "s" "KeyS") `shouldEqual` Just DownloadNow
    shortcut (cmd "o" "KeyO") `shouldEqual` Just ChoosePicture
    shortcut (cmd "s" "KeyS") `shouldEqual` Just DownloadNow
    -- With Caps Lock on
    shortcut (ctrl "O" "KeyO") `shouldEqual` Just ChoosePicture

  it "leaves them to the browser with Shift or Alt, and the letters alone" do
    shortcut ((ctrl "S" "KeyS") { shift = true }) `shouldEqual` Nothing
    -- Ctrl+Alt is AltGr on many keyboards.
    shortcut ((ctrl "o" "KeyO") { alt = true }) `shouldEqual` Nothing
    shortcut (plain "o" "KeyO") `shouldEqual` Nothing
    shortcut (plain "s" "KeyS") `shouldEqual` Nothing
    shortcut (ctrl "p" "KeyP") `shouldEqual` Nothing

  it "finds the letter by its place when the layout's isn't Latin, by its character when it is" do
    -- A Russian layout: Ctrl+щ is the key of O, Ctrl+ы the key of S.
    shortcut (ctrl "щ" "KeyO") `shouldEqual` Just ChoosePicture
    shortcut (ctrl "ы" "KeyS") `shouldEqual` Just DownloadNow
    -- Dvorak: O sits where QWERTY has S, and S where it has semicolon.
    shortcut (ctrl "o" "KeyS") `shouldEqual` Just ChoosePicture
    shortcut (ctrl "s" "Semicolon") `shouldEqual` Just DownloadNow

  it "takes Esc without Ctrl, Alt or Cmd" do
    shortcut (plain "Escape" "Escape") `shouldEqual` Just Escape
    shortcut ((plain "Escape" "Escape") { shift = true }) `shouldEqual` Just Escape
    shortcut (ctrl "Escape" "Escape") `shouldEqual` Nothing
    shortcut ((plain "Escape" "Escape") { alt = true }) `shouldEqual` Nothing

  it "zooms in with + and =, out with −, and leaves Ctrl, Alt and Cmd to the browser" do
    zoomStep (plain "+" "Equal") `shouldEqual` Just 1
    zoomStep (plain "=" "Equal") `shouldEqual` Just 1
    zoomStep (plain "+" "NumpadAdd") `shouldEqual` Just 1
    zoomStep (plain "-" "Minus") `shouldEqual` Just (-1)
    zoomStep (plain "-" "NumpadSubtract") `shouldEqual` Just (-1)
    zoomStep (ctrl "+" "Equal") `shouldEqual` Nothing
    zoomStep (cmd "-" "Minus") `shouldEqual` Nothing
    zoomStep ((plain "-" "Minus") { alt = true }) `shouldEqual` Nothing
    zoomStep (plain "a" "KeyA") `shouldEqual` Nothing

  it "shows the keys in the tooltips, written the same way on every system" do
    texts.withKeys texts.chooseFirst texts.chooseKeys `shouldEqual` "Choose a picture… (Ctrl+O)"
    texts.withKeys "Download PNG" texts.downloadKeys `shouldEqual` "Download PNG (Ctrl+S)"
    texts.withKeys texts.cancel texts.cancelKeys `shouldEqual` "Cancel (Esc)"
