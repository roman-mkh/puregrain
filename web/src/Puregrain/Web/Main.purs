-- | The web UI's page: the app, mounted on the page's body once it's
-- | loaded. Bundled as `app.js` (see web/build.mjs).
module Puregrain.Web.Main (main) where

import Prelude

import Effect (Effect)
import Effect.Class (liftEffect)
import Halogen.Aff as HA
import Halogen.VDom.Driver (runUI)
import Puregrain.Web.App as App
import Puregrain.Web.Page (libraryVersion, prefersDark, setTheme)
import Puregrain.Web.Theme (fromSystem, themeName)

-- | The theme is read from the system before the app's first render, so
-- | a dark system never sees the light theme's logo first.
main :: Effect Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  theme <- liftEffect (fromSystem <$> prefersDark)
  liftEffect (setTheme (themeName theme))
  version <- liftEffect libraryVersion
  runUI App.component { theme, libraryVersion: version } body
