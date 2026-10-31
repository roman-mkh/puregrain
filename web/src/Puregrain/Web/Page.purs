-- | The page around the app: the system's light or dark setting, the
-- | theme on the page's root element, and the library's version, which
-- | the build writes into the page (web/build.mjs).
module Puregrain.Web.Page (prefersDark, setTheme, libraryVersion) where

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
