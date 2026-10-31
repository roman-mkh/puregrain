module Test.Puregrain.Web.DragSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldl)
import Puregrain.Web.Drag (DragStep(..), counted, holdsFiles)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Drag" do
  it "counts the elements a drag has entered, a child's dragenter coming before its parent's dragleave" do
    -- Onto the page, into a child, back to the page, and out of the window.
    let steps = [ Enter, Enter, Leave, Enter, Leave, Leave ]
    Array.drop 1 (Array.scanl counted 0 steps) `shouldEqual` [ 2, 1, 2, 1, 0 ]
    foldl counted 0 steps `shouldEqual` 0

  it "doesn't count below 0, so a stray dragleave can't hide the next drag" do
    foldl counted 0 [ Leave, Leave ] `shouldEqual` 0
    foldl counted 0 [ Leave, Enter ] `shouldEqual` 1

  it "ends the drag at a drop, whatever the count" do
    foldl counted 0 [ Enter, Enter, Enter, Drop ] `shouldEqual` 0

  it "counts only drags that hold files" do
    holdsFiles [ "Files" ] `shouldEqual` true
    holdsFiles [ "application/x-moz-file", "Files" ] `shouldEqual` true
    holdsFiles [ "text/plain", "text/uri-list" ] `shouldEqual` false
    holdsFiles [] `shouldEqual` false
