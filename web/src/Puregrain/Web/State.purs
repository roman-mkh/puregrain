-- | The web UI's state and actions, shared by the component (`App`) and
-- | the modules that render its parts (`View.*`).
module Puregrain.Web.State
  ( Input
  , Load(..)
  , Prepared
  , Run(..)
  , State
  , Action(..)
  , originalRef
  , resultRef
  ) where

import Data.Maybe (Maybe)
import Foreign (Foreign)
import Graphics.Canvas (ImageData)
import Halogen as H
import Halogen.Subscription as HS
import Puregrain.Web.Message (FileBytes)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Prepare (Background, Placement)
import Puregrain.Web.Settings (Settings)
import Puregrain.Web.Theme (Theme)
import Web.Event.Event (Event)
import Web.HTML.Event.DragEvent (DragEvent)
import Web.Worker.Worker (Worker)

-- | What the page knows before the app starts: the theme, from the
-- | system's setting, and the library's version (`Puregrain.Web.Page`).
type Input = { theme :: Theme, libraryVersion :: String }

-- | The picture: none yet, being loaded, failed to load, or loaded, with
-- | the picture as it's shown and dithered.
data Load
  = NoPicture
  | Loading String
  | Failed { name :: String, reason :: String }
  | Loaded { picture :: Picture, prepared :: Prepared }

-- | The picture put onto the background, and for a machine's screen,
-- | when asked, fitted to it (decisions 22 and 27); `fitted` says where it
-- | went on the screen. This is what's shown as the original, and
-- | dithered.
type Prepared =
  { width :: Int
  , height :: Int
  , image :: ImageData
  , fitted :: Maybe { screen :: { width :: Int, height :: Int }, placement :: Placement }
  }

-- | The dithering: none, running (rows done of all, when it started, and
-- | the time left once it's worth showing, decision 23), finished with
-- | the result, a machine's files, and whether saving the PNG failed;
-- | cancelled, or failed.
data Run
  = Idle
  | Running { done :: Int, total :: Int, started :: Number, left :: Maybe Number }
  | Finished { image :: ImageData, files :: Array FileBytes, saveFailed :: Boolean }
  | Cancelled
  | RunFailed String

-- | `loads` and `runs` count the loads and the runs started, so that a
-- | slow load's result, or an answer from a worker already ended, is
-- | dropped. `typed` keeps the threshold and the number of levels last
-- | typed, for when those colors are chosen again. `split` is the
-- | picture's columns that show the original, left of the result. `fit`
-- | and `background` prepare every picture loaded.
type State =
  { load :: Load
  , loads :: Int
  , zoom :: Int
  , pixelRatio :: Number
  , split :: Int
  , fit :: Boolean
  , background :: Background
  , settings :: Settings
  , typed :: { threshold :: Int, levels :: Int }
  , run :: Run
  , runs :: Int
  , worker :: Maybe Worker
  , listener :: Maybe (HS.Listener Action)
  , theme :: Theme
  , libraryVersion :: String
  }

data Action
  = Initialize
  | Resized
  | ThemeToggled
  | FileChosen Event
  | DragOver DragEvent
  | Dropped DragEvent
  | ZoomChosen String
  | TargetChosen String
  | FitChosen Boolean
  | BackgroundChosen String
  | ColorsChosen String
  | ThresholdTyped String
  | LevelsTyped String
  | KernelChosen String
  | BayerChosen String
  | GrayChosen Boolean
  | Cancel
  | FromWorker Int Foreign
  | SplitMoved String
  | Save
  | SaveFile String

-- | The canvases of the original and of the result.
originalRef :: H.RefLabel
originalRef = H.RefLabel "original"

resultRef :: H.RefLabel
resultRef = H.RefLabel "result"
