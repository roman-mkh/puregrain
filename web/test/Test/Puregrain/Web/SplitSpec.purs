module Test.Puregrain.Web.SplitSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Split (columnAt, grabAt, keyed)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Split" do
  it "puts the split on the nearest boundary between columns, within the picture" do
    columnAt 0.5 320 `shouldEqual` 160
    columnAt 0.0 320 `shouldEqual` 0
    columnAt 1.0 320 `shouldEqual` 320
    -- 0.49 and 0.51 of the first column
    columnAt (0.49 / 320.0) 320 `shouldEqual` 0
    columnAt (0.51 / 320.0) 320 `shouldEqual` 1
    -- the pointer left or right of the picture
    columnAt (-0.2) 320 `shouldEqual` 0
    columnAt 1.3 320 `shouldEqual` 320

  it "follows the pointer from where it took hold, so the line doesn't jump" do
    -- Taken hold of a tenth of the width right of the line at 160.
    let grab = grabAt 0.6 160 320
    columnAt (0.6 - grab) 320 `shouldEqual` 160
    -- Moved left by a quarter of the width: 80 columns.
    columnAt (0.35 - grab) 320 `shouldEqual` 80
    -- On the line itself, nothing to take off.
    grabAt 0.5 160 320 `shouldEqual` 0.0

  it "moves a column with the arrow keys, ten with Shift, and to the edges with Home and End" do
    let key k = { key: k, shift: false, modified: false }
    keyed (key "ArrowRight") 160 320 `shouldEqual` Just 161
    keyed (key "ArrowLeft") 160 320 `shouldEqual` Just 159
    keyed { key: "ArrowRight", shift: true, modified: false } 160 320 `shouldEqual` Just 170
    keyed { key: "ArrowLeft", shift: true, modified: false } 160 320 `shouldEqual` Just 150
    keyed (key "Home") 160 320 `shouldEqual` Just 0
    keyed (key "End") 160 320 `shouldEqual` Just 320

  it "stops at the picture's edges" do
    let key k = { key: k, shift: false, modified: false }
    keyed (key "ArrowLeft") 0 320 `shouldEqual` Just 0
    keyed { key: "ArrowRight", shift: true, modified: false } 315 320 `shouldEqual` Just 320
    keyed { key: "ArrowLeft", shift: true, modified: false } 4 320 `shouldEqual` Just 0

  it "leaves every other key to the browser, and the arrows with Ctrl, Alt or Meta" do
    let key k = { key: k, shift: false, modified: false }
    keyed (key "ArrowUp") 160 320 `shouldEqual` Nothing
    keyed (key "ArrowDown") 160 320 `shouldEqual` Nothing
    keyed (key "PageUp") 160 320 `shouldEqual` Nothing
    keyed (key "Tab") 160 320 `shouldEqual` Nothing
    keyed (key "+") 160 320 `shouldEqual` Nothing
    keyed { key: "ArrowLeft", shift: false, modified: true } 160 320 `shouldEqual` Nothing
    keyed { key: "Home", shift: false, modified: true } 160 320 `shouldEqual` Nothing
