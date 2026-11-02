-- | Files dragged over the page (decisions 30 D and 34 in
-- | web/ROADMAP.md). The browser fires `dragenter` and `dragleave` for
-- | each element the pointer enters and leaves, children included, and
-- | the new element's `dragenter` comes before the old one's
-- | `dragleave`. So the page counts them: a file is over the page while
-- | the count is above 0. Only drags that hold files count; dragging text
-- | or a link over the page shows nothing. Pure, so specs test it.
module Puregrain.Web.Drag
  ( DragStep(..)
  , counted
  , holdsFiles
  ) where

import Prelude

import Data.Array as Array

-- | What a drag did: entered an element, left one, or dropped.
data DragStep = Enter | Leave | Drop

-- | The count after a step: up when the drag enters an element, down when
-- | it leaves one, never below 0; a drop ends the drag.
counted :: Int -> DragStep -> Int
counted n = case _ of
  Enter -> n + 1
  Leave -> max 0 (n - 1)
  Drop -> 0

-- | Whether a drag holds files, from its data's types (`DataTransfer`'s
-- | `types`), which can be read while the drag is still going on.
holdsFiles :: Array String -> Boolean
holdsFiles = Array.elem "Files"
