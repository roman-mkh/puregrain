-- | The controls the settings are made of (decision 31): a numbered step,
-- | cards and segments (radio buttons), a stepper, a toggle switch, a
-- | note, and a file chooser that looks like a button. Plain HTML
-- | controls underneath, so the keyboard and screen readers work as
-- | usual (decision 33); `app.css` gives them their look.
module Puregrain.Web.View.Controls
  ( step
  , cards
  , segments
  , stepper
  , toggleSwitch
  , note
  , fileButton
  ) where

import Prelude

import Data.Int (toNumber)
import Data.Maybe (Maybe, maybe)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
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

-- | Choices with a line of explanation each: radio buttons, one per card.
-- | `ref` names the selected one, for moving the focus there.
cards
  :: forall w i
   . { name :: String, label :: String, selected :: String, pick :: String -> i, ref :: Maybe H.RefLabel }
  -> Array { value :: String, title :: String, line :: String }
  -> HH.HTML w i
cards group items =
  HH.div [ HP.class_ (H.ClassName "cards"), HP.attr (H.AttrName "role") "radiogroup", HP.attr (H.AttrName "aria-label") group.label ]
    ( items <#> \item ->
        HH.label [ HP.class_ (H.ClassName "card") ]
          [ let
              chosen = item.value == group.selected
            in
              HH.input
                ( [ HP.type_ HP.InputRadio
                  , HP.name group.name
                  , HP.value item.value
                  , HP.checked chosen
                  , HE.onChange (const (group.pick item.value))
                  ]
                    <> (if chosen then maybe [] (\r -> [ HP.ref r ]) group.ref else [])
                )
          , HH.span_
              [ HH.b_ [ HH.text item.title ]
              , HH.small_ [ HH.text item.line ]
              ]
          ]
    )

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
toggleSwitch :: forall w i. { label :: String, checked :: Boolean, toggle :: Boolean -> i } -> HH.HTML w i
toggleSwitch s =
  HH.label [ HP.class_ (H.ClassName "switch") ]
    [ HH.input
        [ HP.type_ HP.InputCheckbox
        , HP.attr (H.AttrName "role") "switch"
        , HP.checked s.checked
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
