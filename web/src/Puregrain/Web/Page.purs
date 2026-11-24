-- | The page around the app: the system's light or dark setting, the
-- | theme on the page's root element, the engine check's result there,
-- | the library's version, which the build writes into the page
-- | (web/build.mjs), whether the screen is a phone's, the platform's
-- | name, a file of the page's kept in memory, and a warning in the
-- | browser's console.
module Puregrain.Web.Page (prefersDark, setTheme, setEngineCheck, libraryVersion, narrowScreen, platform, keptInMemory, warnInConsole) where

import Prelude

import Control.Promise (Promise, toAffE)
import Effect (Effect)
import Effect.Aff (Aff)
import Web.HTML (window)
import Web.HTML.Navigator as Navigator
import Web.HTML.Window as Window

-- | Whether the system asks for a dark theme (`prefers-color-scheme`).
foreign import prefersDark :: Effect Boolean

-- | Puts a theme's name on the page's root element, `data-theme`, so that
-- | the whole page follows it, its background and scrollbars included.
foreign import setTheme :: String -> Effect Unit

-- | Puts the engine check's state on the page's root element,
-- | `data-engine-check` (`Puregrain.Web.Status.engineCheckName`), for
-- | checks of the page from outside.
foreign import setEngineCheck :: String -> Effect Unit

-- | A warning in the browser's console, for whoever reports a problem.
foreign import warnInConsole :: String -> Effect Unit

-- | The library's version, from the page's `puregrain-version` meta
-- | element; empty when the build hasn't filled it in.
foreign import libraryVersion :: Effect String

-- | Whether the page has a phone's layout: the stylesheet's limit, 760
-- | pixels wide (decision 29).
foreign import narrowScreen :: Effect Boolean

-- | The platform's name, `navigator.platform` ("MacIntel", "Win32",
-- | "Linux x86_64"…), for telling a Mac (`Puregrain.Web.Keys.macPlatform`).
platform :: Effect String
platform = window >>= Window.navigator >>= Navigator.platform

foreign import keptInMemoryImpl :: String -> Effect (Promise String)

-- | A file of the page's, by its address, fetched once and kept in
-- | memory: the address of the copy (a Blob URL), valid for the page's
-- | lifetime, or the file's own address when it can't be fetched.
keptInMemory :: String -> Aff String
keptInMemory path = toAffE (keptInMemoryImpl path)
