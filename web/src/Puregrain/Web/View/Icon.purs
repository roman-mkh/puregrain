-- | Small icons, inline SVG drawn in the text's color (decision 34): a
-- | character such as ☾ or ☼ would look different from system to system,
-- | and as emoji on some.
module Puregrain.Web.View.Icon (sun, moon, chevronsLeft, chevronsRight, leftRight, caretDown) where

import Prelude

import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

-- | A sun: the light theme.
sun :: forall w i. HH.HTML w i
sun = icon
  [ "M8 4.5a3.5 3.5 0 1 1 0 7a3.5 3.5 0 1 1 0-7z"
  , "M7.25 0h1.5v2.5h-1.5zM7.25 13.5h1.5v2.5h-1.5zM0 7.25h2.5v1.5h-2.5zM13.5 7.25h2.5v1.5h-2.5z"
  , "M2.83 1.77L4.63 3.57L3.57 4.63L1.77 2.83zM13.17 1.77L14.23 2.83L12.43 4.63L11.37 3.57z"
  , "M2.83 14.23L1.77 13.17L3.57 11.37L4.63 12.43zM13.17 14.23L11.37 12.43L12.43 11.37L14.23 13.17z"
  ]

-- | A crescent moon: the dark theme.
moon :: forall w i. HH.HTML w i
moon = icon [ "M6.2 1.2A7 7 0 1 0 14.8 9.8A5.5 5.5 0 0 1 6.2 1.2z" ]

-- | « : the settings' column slides away to the left.
chevronsLeft :: forall w i. HH.HTML w i
chevronsLeft = icon [ "M7 3 2 8l5 5 1.4-1.4L4.8 8l3.6-3.6zM13 3 8 8l5 5 1.4-1.4L10.8 8l3.6-3.6z" ]

-- | » : the settings' column comes back.
chevronsRight :: forall w i. HH.HTML w i
chevronsRight = icon [ "M9 3l5 5-5 5-1.4-1.4L11.2 8 7.6 4.4zM3 3l5 5-5 5-1.4-1.4L5.2 8 1.6 4.4z" ]

-- | ◂ ▸ : the split handle's knob, dragged sideways.
leftRight :: forall w i. HH.HTML w i
leftRight = icon [ "M6 3.5 1 8l5 4.5zM10 3.5l5 4.5-5 4.5z" ]

-- | ▾ : a list opens from the button.
caretDown :: forall w i. HH.HTML w i
caretDown = icon [ "M3.5 6h9L8 11z" ]

-- | 16 × 16, hidden from screen readers: the button it's in has a name.
icon :: forall w i. Array String -> HH.HTML w i
icon paths =
  HH.elementNS svg (HH.ElemName "svg")
    [ HP.attr (HH.AttrName "viewBox") "0 0 16 16"
    , HP.attr (HH.AttrName "width") "16"
    , HP.attr (HH.AttrName "height") "16"
    , HP.attr (HH.AttrName "aria-hidden") "true"
    , HP.attr (HH.AttrName "focusable") "false"
    ]
    (map path paths)
  where
  path d = HH.elementNS svg (HH.ElemName "path") [ HP.attr (HH.AttrName "d") d, HP.attr (HH.AttrName "fill") "currentColor" ] []
  svg = HH.Namespace "http://www.w3.org/2000/svg"
