-- | The web UI's state and actions, shared by the component (`App`) and
-- | the modules that render its parts (`View.*`).
module Puregrain.Web.State
  ( Input
  , Load(..)
  , Prepared
  , State
  , Action(..)
  , originalRef
  , resultRef
  , layersRef
  , handleRef
  ) where

import Data.Maybe (Maybe)
import Foreign (Foreign)
import Graphics.Canvas (ImageData)
import Halogen as H
import Halogen.Subscription as HS
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Prepare (Background, Placement)
import Puregrain.Web.Settings (Settings)
import Puregrain.Web.Status (Run)
import Puregrain.Web.Theme (Theme)
import Web.Event.Event (Event)
import Web.HTML.Event.DragEvent (DragEvent)
import Web.UIEvent.KeyboardEvent (KeyboardEvent)
import Web.Worker.Worker (Worker)

-- | What the page knows before the app starts: the theme, from the
-- | system's setting, and the library's version (`Puregrain.Web.Page`).
type Input = { theme :: Theme, libraryVersion :: String }

-- | The picture: none yet, or loaded, with the picture as it's shown and
-- | dithered. One being loaded doesn't replace it until it has decoded
-- | (decision 30 C).
data Load
  = NoPicture
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

-- | `loads` and `runs` count the loads and the runs started, so that a
-- | slow load's result, or an answer from a worker already ended, is
-- | dropped. `loading` is the name of the file being loaded, and
-- | `notAPicture` the name of the last one that couldn't be, until the
-- | next load or setting (decision 30 A and C). `typed` keeps the
-- | threshold and the number of levels last typed, for when those colors
-- | are chosen again. `split` is the picture's columns that show the
-- | original, left of the result; `splitDrag` the pointer dragging its
-- | handle, and where it took hold (`Puregrain.Web.Split`). `fit` and
-- | `background` prepare every picture loaded. `dragged` counts what a
-- | drag of files has entered (`Puregrain.Web.Drag`). `columnHidden` is
-- | the settings' column slid away (decision 29).
type State =
  { load :: Load
  , loads :: Int
  , loading :: Maybe String
  , notAPicture :: Maybe String
  , zoom :: Int
  , pixelRatio :: Number
  , split :: Int
  , splitDrag :: Maybe { pointer :: Int, grab :: Number }
  , fit :: Boolean
  , background :: Background
  , settings :: Settings
  , typed :: { threshold :: Int, levels :: Int }
  , run :: Run
  , runs :: Int
  , worker :: Maybe Worker
  , listener :: Maybe (HS.Listener Action)
  , dragged :: Int
  , theme :: Theme
  , libraryVersion :: String
  , columnHidden :: Boolean
  }

data Action
  = Initialize
  | Resized
  | ThemeToggled
  | ColumnToggled
  | FileChosen Event
  | DragEntered DragEvent
  | DragLeft DragEvent
  | DragOver DragEvent
  | Dropped DragEvent
  | ZoomChosen String
  | TargetChosen String
  | FitChosen Boolean
  | BackgroundChosen String
  | ColorsChosen String
  | ThresholdTyped String
  | ThresholdDragged String
  | LevelsTyped String
  | KernelChosen String
  | BayerChosen String
  | GrayChosen Boolean
  | Cancel
  | FromWorker Int Foreign
  | SplitPressed Event
  | SplitDragged Event
  | SplitReleased Event
  | SplitKey KeyboardEvent
  | Save
  | SaveFile String

-- | The canvases of the original and of the result, the box holding
-- | them, and the split's handle.
originalRef :: H.RefLabel
originalRef = H.RefLabel "original"

resultRef :: H.RefLabel
resultRef = H.RefLabel "result"

layersRef :: H.RefLabel
layersRef = H.RefLabel "layers"

handleRef :: H.RefLabel
handleRef = H.RefLabel "handle"
