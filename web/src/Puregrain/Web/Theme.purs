-- | The page's two themes (decision 32 in web/ROADMAP.md): dark with the
-- | ZX Spectrum's set of the logo and its green, light with the C64's set
-- | and its blue. A page starts from the system's setting, and the switch
-- | toggles it; the choice isn't kept, so the next load starts from the
-- | system's again.
module Puregrain.Web.Theme
  ( Theme(..)
  , fromSystem
  , toggled
  , themeName
  ) where

import Prelude

data Theme = Light | Dark

derive instance Eq Theme

instance Show Theme where
  show = themeName

-- | The theme a page starts with: dark when the system asks for it.
fromSystem :: Boolean -> Theme
fromSystem dark = if dark then Dark else Light

-- | The other theme.
toggled :: Theme -> Theme
toggled = case _ of
  Light -> Dark
  Dark -> Light

-- | The theme's name on the page's root element, `data-theme`, which the
-- | stylesheet reads.
themeName :: Theme -> String
themeName = case _ of
  Light -> "light"
  Dark -> "dark"
