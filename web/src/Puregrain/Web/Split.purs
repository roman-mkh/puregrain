-- | The split handle (decision 31 in web/ROADMAP.md): the original left
-- | of the split, the result right of it, the split always at a boundary
-- | between the picture's columns, from 0 to the picture's width. The
-- | handle is dragged by the pointer, or moved by the keys while it has
-- | the focus, like a slider. Pure, so specs test it.
module Puregrain.Web.Split
  ( columnAt
  , grabAt
  , Key
  , keyed
  ) where

import Prelude

import Data.Int (round, toNumber)
import Data.Maybe (Maybe(..))

-- | The split for a place across the picture.
-- |
-- | - `across`: 0 at the picture's left edge, 1 at its right edge.
-- | - `width`: the picture's width, in columns.
-- |
-- | The result is the nearest boundary between columns, within the
-- | picture.
columnAt :: Number -> Int -> Int
columnAt across width = clamp 0 width (round (across * toNumber width))

-- | Where the pointer took hold of the handle, relative to its line, so
-- | that the line doesn't jump to the pointer when the drag begins.
-- |
-- | - `across`: the pointer's place across the picture, as for `columnAt`.
-- | - `split`: the split when the pointer took hold.
-- | - `width`: the picture's width, in columns.
-- |
-- | The result, in the same unit as `across`, is what a drag takes off
-- | the pointer's place: `columnAt (across - grab) width`.
grabAt :: Number -> Int -> Int -> Number
grabAt across split width = across - toNumber split / toNumber width

-- | A key pressed on the handle: its name (`KeyboardEvent`'s `key`),
-- | whether Shift was held, and whether Ctrl, Alt or Meta was.
type Key = { key :: String, shift :: Boolean, modified :: Boolean }

-- | The split a key moves the handle to: ← and → one column, with Shift
-- | ten, Home and End to the edges, within the picture.
-- |
-- | - `Key`: the key pressed.
-- | - `split`: the split now.
-- | - `width`: the picture's width, in columns.
-- |
-- | `Nothing` for any other key, and with Ctrl, Alt or Meta held: those
-- | stay the browser's (Alt+← goes back a page, ↑ and ↓ scroll).
keyed :: Key -> Int -> Int -> Maybe Int
keyed k split width =
  if k.modified then Nothing
  else clamp 0 width <$> case k.key of
    "ArrowLeft" -> Just (split - step)
    "ArrowRight" -> Just (split + step)
    "Home" -> Just 0
    "End" -> Just width
    _ -> Nothing
  where
  step = if k.shift then 10 else 1
