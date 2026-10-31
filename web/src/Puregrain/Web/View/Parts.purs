-- | Small pieces the views share: a menu's option, the `inert` property,
-- | and the links to the project on GitHub.
module Puregrain.Web.View.Parts
  ( option
  , inert
  , repositoryUrl
  , helpUrl
  , licenseUrl
  , logoTermsUrl
  ) where

import Prelude

import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

option :: forall w i. String -> String -> Boolean -> HH.HTML w i
option value label selected = HH.option [ HP.value value, HP.selected selected ] [ HH.text label ]

-- | Out of the user's reach, keyboard and screen readers included, while
-- | the phone's settings panel is over the page (decision 34).
inert :: forall r i. Boolean -> HP.IProp r i
inert = HP.prop (H.PropName "inert")

repositoryUrl :: String
repositoryUrl = "https://github.com/roman-mkh/puregrain"

-- | The web UI's user docs, from "Using it" on.
helpUrl :: String
helpUrl = repositoryUrl <> "/blob/master/web/README.md#using-it"

licenseUrl :: String
licenseUrl = repositoryUrl <> "/blob/master/LICENSE"

logoTermsUrl :: String
logoTermsUrl = repositoryUrl <> "/blob/master/logo/LICENSE.md"
