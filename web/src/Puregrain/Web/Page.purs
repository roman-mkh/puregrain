-- | The page around the app: the system's light or dark setting, the
-- | theme on the page's root element, the library's version, which the
-- | build writes into the page (web/build.mjs), whether the screen is a
-- | phone's, and a file of the page's kept in memory.
module Puregrain.Web.Page (prefersDark, setTheme, libraryVersion, narrowScreen, keptInMemory) where

import Prelude

import Control.Promise (Promise, toAffE)
import Effect (Effect)
import Effect.Aff (Aff)

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

foreign import keptInMemoryImpl :: String -> Effect (Promise String)

-- | A file of the page's, by its address, fetched once and kept in
-- | memory: the address of the copy (a Blob URL), valid for the page's
-- | lifetime, or the file's own address when it can't be fetched.
keptInMemory :: String -> Aff String
keptInMemory path = toAffE (keptInMemoryImpl path)
