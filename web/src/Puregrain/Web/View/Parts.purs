-- | Small pieces the views share: a menu's option, and the links to the
-- | project on GitHub.
module Puregrain.Web.View.Parts
  ( option
  , repositoryUrl
  , helpUrl
  , licenseUrl
  , logoTermsUrl
  ) where

import Prelude

import Halogen.HTML as HH
import Halogen.HTML.Properties as HP

option :: forall w i. String -> String -> Boolean -> HH.HTML w i
option value label selected = HH.option [ HP.value value, HP.selected selected ] [ HH.text label ]

repositoryUrl :: String
repositoryUrl = "https://github.com/roman-mkh/puregrain"

-- | The web UI's user docs, from "Using it" on.
helpUrl :: String
helpUrl = repositoryUrl <> "/blob/master/web/README.md#using-it"

licenseUrl :: String
licenseUrl = repositoryUrl <> "/blob/master/LICENSE"

logoTermsUrl :: String
logoTermsUrl = repositoryUrl <> "/blob/master/logo/LICENSE.md"
