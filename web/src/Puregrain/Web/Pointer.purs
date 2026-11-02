-- | The pointer's events, read for the split handle: Halogen 7.0.0 has no
-- | pointer events of its own, so the handle takes them as plain events
-- | (decision 34 in web/ROADMAP.md).
module Puregrain.Web.Pointer
  ( pointerId
  , mainButton
  , pressed
  , across
  , capture
  ) where

import Prelude (Unit)

import Effect (Effect)
import Web.Event.Event (Event)
import Web.HTML.HTMLElement (HTMLElement)

-- | The pointer's number, which tells several pointers apart (fingers,
-- | say).
foreign import pointerId :: Event -> Int

-- | Whether a `pointerdown` came from the main button: a mouse's left
-- | button, or a finger's or a pen's touch.
foreign import mainButton :: Event -> Boolean

-- | Whether a button is still held, or the finger or the pen still
-- | touches.
foreign import pressed :: Event -> Boolean

-- | The pointer's place across an element: 0 at its left edge, 1 at its
-- | right edge, and beyond them outside it.
foreign import across :: Event -> HTMLElement -> Effect Number

-- | Sends the pointer's next events to the element, also when the
-- | pointer leaves it, until the button is released or the touch ends;
-- | meanwhile no text selection starts on the page.
foreign import capture :: HTMLElement -> Int -> Effect Unit
