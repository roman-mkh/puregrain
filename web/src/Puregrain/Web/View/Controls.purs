-- | The controls the settings are made of (decision 31): a numbered step,
-- | a menu that looks like a card (decision 37), segments (radio buttons),
-- | a stepper, a toggle switch, a note, a file chooser that looks like a
-- | button, and a sentence with a button that looks like a link. Plain
-- | HTML controls underneath, so the keyboard and screen readers work as
-- | usual (decision 33); `app.css` gives them their look.
module Puregrain.Web.View.Controls
  ( step
  , cardMenu
  , segments
  , stepper
  , toggleSwitch
  , note
  , fileButton
  , withLink
  , mainLink
  , keysAfter
  ) where

import Prelude

import Data.Array as Array
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), maybe)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.View.Icon as Icon
import Puregrain.Web.View.Parts (option)
import Web.Event.Event (Event)

-- | A numbered step: a group with its heading, disabled with all it holds.
step :: forall w i. Int -> String -> Boolean -> Array (HH.HTML w i) -> HH.HTML w i
step number title disabled body =
  HH.fieldset [ HP.class_ (H.ClassName "step"), HP.disabled disabled ]
    ( [ HH.legend_
          [ HH.span [ HP.class_ (H.ClassName "step-number") ] [ HH.text (show number) ]
          , HH.text title
          ]
      ]
        <> body
    )

-- | Choices with a line of explanation each, as a menu that looks like a
-- | card (decision 37): a face shows the chosen one's title and line, with
-- | ▾, and over it lies a native `<select>`, invisible, which takes the
-- | clicks, the keys and the focus, and opens the browser's own list (a
-- | picker on phones). Screen readers hear the select, named `label` and
-- | described by the line; the face is hidden from them. `name` makes the
-- | line's id; `ref` names the select, for moving the focus there. With no
-- | item `selected`, the face shows the first, as the select does.
cardMenu
  :: forall w i
   . { name :: String, label :: String, selected :: String, pick :: String -> i, ref :: Maybe H.RefLabel }
  -> Array { value :: String, title :: String, line :: String }
  -> HH.HTML w i
cardMenu menu items =
  HH.div [ HP.class_ (H.ClassName "card-menu") ]
    [ HH.span [ HP.class_ (H.ClassName "face"), HP.attr (H.AttrName "aria-hidden") "true" ]
        [ HH.b_ [ HH.text chosen.title ]
        , HH.small [ HP.id lineId ] [ HH.text chosen.line ]
        ]
    , Icon.caretDown
    , HH.select
        ( [ HP.attr (H.AttrName "aria-label") menu.label
          , HP.attr (H.AttrName "aria-describedby") lineId
          , HE.onValueChange menu.pick
          ]
            <> maybe [] (\r -> [ HP.ref r ]) menu.ref
        )
        (items <#> \item -> option item.value item.title (item.value == menu.selected))
    ]
  where
  lineId = menu.name <> "-line"
  chosen = case Array.find (\item -> item.value == menu.selected) items, Array.head items of
    Just item, _ -> item
    Nothing, Just first -> first
    Nothing, Nothing -> { value: "", title: "", line: "" }

-- | A row of short choices: radio buttons drawn as segments, labelled by
-- | the element `labelledBy` names.
segments
  :: forall w i
   . { name :: String, labelledBy :: String, selected :: String, disabled :: Boolean, pick :: String -> i }
  -> Array { value :: String, text :: String }
  -> HH.HTML w i
segments group items =
  HH.div [ HP.class_ (H.ClassName "segments"), HP.attr (H.AttrName "role") "radiogroup", HP.attr (H.AttrName "aria-labelledby") group.labelledBy ]
    ( items <#> \item ->
        HH.label_
          [ radio group.name item.value (item.value == group.selected) group.disabled (group.pick item.value)
          , HH.span_ [ HH.text item.text ]
          ]
    )

radio :: forall w i. String -> String -> Boolean -> Boolean -> i -> HH.HTML w i
radio name value checked disabled action =
  HH.input
    [ HP.type_ HP.InputRadio
    , HP.name name
    , HP.value value
    , HP.checked checked
    , HP.disabled disabled
    , HE.onChange (const action)
    ]

-- | A number between − and + buttons, within `low` and `high`; the buttons
-- | stop at the ends. `set` gets the new number as typed text, as the
-- | number's own input does.
stepper
  :: forall w i
   . { labelledBy :: String, value :: Int, low :: Int, high :: Int, fewer :: String, more :: String, set :: String -> i }
  -> HH.HTML w i
stepper s =
  HH.div [ HP.class_ (H.ClassName "stepper") ]
    [ button s.fewer "−" (s.value <= s.low) (s.value - 1)
    , HH.input
        [ HP.type_ HP.InputNumber
        , HP.min (toNumber s.low)
        , HP.max (toNumber s.high)
        , HP.value (show s.value)
        , HP.attr (H.AttrName "aria-labelledby") s.labelledBy
        , HE.onValueInput s.set
        ]
    , button s.more "+" (s.value >= s.high) (s.value + 1)
    ]
  where
  button label sign disabled to =
    HH.button
      [ HP.type_ HP.ButtonButton
      , HP.attr (H.AttrName "aria-label") label
      , HP.title label
      , HP.disabled disabled
      , HE.onClick (const (s.set (show to)))
      ]
      [ HH.text sign ]

-- | A toggle switch: a checkbox marked as a switch for screen readers, since
-- | by the usual convention a switch takes effect at once (decision 31).
toggleSwitch :: forall w i. { label :: String, checked :: Boolean, disabled :: Boolean, toggle :: Boolean -> i } -> HH.HTML w i
toggleSwitch s =
  HH.label [ HP.class_ (H.ClassName "switch") ]
    [ HH.input
        [ HP.type_ HP.InputCheckbox
        , HP.attr (H.AttrName "role") "switch"
        , HP.checked s.checked
        , HP.disabled s.disabled
        , HE.onChecked s.toggle
        ]
    , HH.span [ HP.class_ (H.ClassName "track"), HP.attr (H.AttrName "aria-hidden") "true" ] []
    , HH.text s.label
    ]

-- | A note beside the setting it's about.
note :: forall w i. Array (HH.HTML w i) -> HH.HTML w i
note = HH.p [ HP.class_ (H.ClassName "note") ]

-- | A file chooser that looks like a button: a label around the file
-- | input, which is hidden but still takes the focus and the keys. The
-- | `title` shows as its tooltip; `ref` names the input, for opening it
-- | from code.
fileButton
  :: forall w i
   . { label :: String, title :: String, primary :: Boolean, ref :: Maybe H.RefLabel, chosen :: Event -> i }
  -> HH.HTML w i
fileButton f =
  HH.label [ HP.classes ([ H.ClassName "file-button" ] <> (if f.primary then [ H.ClassName "primary" ] else [])), HP.title f.title ]
    [ HH.input
        ( [ HP.type_ HP.InputFile
          , HP.class_ (H.ClassName "sr-only")
          , HP.attr (H.AttrName "accept") "image/*"
          , HE.onChange f.chosen
          ]
            <> maybe [] (\r -> [ HP.ref r ]) f.ref
        )
    , HH.text f.label
    ]

-- | A button that looks like a link, for a main way in (v2.6's "paste"):
-- | in the accent color, where a hint's other links are in its gray.
mainLink :: forall w i. String -> i -> HH.HTML w i
mainLink text action =
  HH.button [ HP.type_ HP.ButtonButton, HP.classes [ H.ClassName "link", H.ClassName "main" ], HE.onClick (const action) ] [ HH.text text ]

-- | The keys for what a sentence offers, after it in brackets; hidden on
-- | phones, which have no keyboard.
keysAfter :: forall w i. String -> HH.HTML w i
keysAfter keys = HH.span [ HP.class_ (H.ClassName "off-phone") ] [ HH.text (" (" <> keys <> ")") ]

-- | A sentence with a link in it: a button that looks like a link, since
-- | it acts on this page rather than leading elsewhere (as "Use 2×2" does
-- | in a note). The text comes in parts around the link.
withLink :: forall w i. { before :: String, link :: String, after :: String } -> i -> Array (HH.HTML w i)
withLink text action =
  [ HH.text text.before
  , HH.button [ HP.type_ HP.ButtonButton, HP.class_ (H.ClassName "link"), HE.onClick (const action) ] [ HH.text text.link ]
  , HH.text text.after
  ]
