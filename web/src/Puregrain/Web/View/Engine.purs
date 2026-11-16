-- | The engine check's icon and its popup (`Puregrain.Web.Status`): a
-- | button showing the check's state, gray
-- | while it runs, then passed or failed, which opens a sentence about it
-- | with a link to the details in the README. It opens and closes as the
-- | download's list of formats does (decision 31): Escape and a click
-- | outside close it, the focus going back to the button.
module Puregrain.Web.View.Engine (engineCheck) where

import Prelude

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Puregrain.Web.State (Action(..), engineButtonRef, engineRef)
import Puregrain.Web.Status (EngineCheck(..))
import Puregrain.Web.Text (texts)
import Puregrain.Web.View.Icon as Icon
import Puregrain.Web.View.Parts (engineCheckUrl)

-- | `place`: `"top"` in the header, `"foot"` in the footer, which opens
-- | its popup upwards. Each place has its own ids and refs; the
-- | stylesheet shows one of them.
engineCheck :: forall w. { check :: EngineCheck, open :: Boolean, place :: String } -> HH.HTML w Action
engineCheck { check, open, place } =
  HH.span [ HP.ref (engineRef place), HP.class_ (H.ClassName "engine") ]
    [ HH.button
        [ HP.ref (engineButtonRef place)
        , HP.type_ HP.ButtonButton
        , HP.class_ (H.ClassName ("engine-button " <> state))
        , HP.attr (HH.AttrName "aria-expanded") (if open then "true" else "false")
        , HP.attr (HH.AttrName "aria-controls") box
        , HE.onClick (const EngineToggled)
        ]
        [ icon
        , HH.span [ HP.class_ (H.ClassName "sr-only") ] [ HH.text (texts.engineName check) ]
        ]
    , HH.div [ HP.id box, HP.class_ (H.ClassName "engine-box"), HP.prop (H.PropName "hidden") (not open) ]
        [ HH.p_ [ HH.text (texts.engineStatus check) ]
        , HH.a [ HP.href engineCheckUrl ] [ HH.text texts.engineDetails ]
        ]
    ]
  where
  box = "engine-box-" <> place
  { state, icon } = case check of
    EngineChecking -> { state: "checking", icon: Icon.engineChecking }
    EnginePassed -> { state: "passed", icon: Icon.enginePassed }
    EngineFailed _ -> { state: "failed", icon: Icon.engineFailed }
    EngineNotRun -> { state: "checking", icon: Icon.engineChecking }
