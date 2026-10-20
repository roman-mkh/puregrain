-- | All the texts the web UI shows, in one place, so that a translation
-- | could replace them later (decision 12 in web/ROADMAP.md).
module Puregrain.Web.Text (texts) where

import Prelude

texts
  :: { title :: String
     , choose :: String
     , loading :: String -> String
     , failed :: { name :: String, reason :: String } -> String
     , loaded :: { name :: String, width :: Int, height :: Int } -> String
     , zoom :: String
     , zoomLevel :: Int -> String
     }
texts =
  { title: "puregrain"
  , choose: "Choose a picture, or drop one onto this page."
  , loading: \name -> "Loading " <> name <> "..."
  , failed: \f -> f.name <> " couldn't be read as a picture (" <> f.reason <> ")."
  , loaded: \p -> p.name <> ": " <> show p.width <> " × " <> show p.height <> " pixels"
  , zoom: "Zoom"
  , zoomLevel: \zoom -> show zoom <> "×"
  }
