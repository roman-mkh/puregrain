-- | The page around the app: the system's light or dark setting, the
-- | theme on the page's root element, the library's version, which the
-- | build writes into the page (web/build.mjs), and whether the screen is
-- | a phone's.
module Puregrain.Web.Page (prefersDark, setTheme, libraryVersion, narrowScreen) where

import Prelude

import Effect (Effect)

-- | Whether the system asks for a dark theme (`prefers-color-scheme`).
foreign import prefersDark :: Effect Boolean

-- | Puts a theme's name on the page's root element, `data-theme`, so that
-- | the whole page follows it, its background and scrollbars included.
foreign import setTheme :: String -> Effect Unit

-- | The library's version, from the page's `puregrain-version` meta
-- | element; empty when the build hasn't filled it in.
foreign import libraryVersion :: Effect String

-- | Whether the page has a phone's layout: the stylesheet's limit, 760
-- | pixels wide (decision 29).
foreign import narrowScreen :: Effect Boolean
