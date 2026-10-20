-- | All the texts the web UI shows, in one place, so that a translation
-- | could replace them later (decision 12 in web/ROADMAP.md).
module Puregrain.Web.Text (texts) where

import Prelude

texts
  :: { title :: String
     , workerStarting :: String
     , workerAnswered :: String -> String
     }
texts =
  { title: "puregrain"
  , workerStarting: "Starting the worker..."
  , workerAnswered: \answer -> "The worker answered: " <> answer
  }
