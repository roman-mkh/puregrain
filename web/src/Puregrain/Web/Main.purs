-- | The web UI's page: the app, mounted on the page's body once it's
-- | loaded. Bundled as `app.js` (see web/build.mjs).
module Puregrain.Web.Main (main) where

import Prelude

import Effect (Effect)
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Puregrain.Web.App as App

main :: Effect Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  runUI App.component unit body
