-- | The web UI's state and actions, shared by the component (`App`) and
-- | the modules that render its parts (`View.*`).
module Puregrain.Web.State
  ( Input
  , Load(..)
  , Prepared
  , State
  , Said
  , Action(..)
  , downloadName
  , originalRef
  , resultRef
  , layersRef
  , handleRef
  , chooserRef
  , downloadsRef
  , formatsRef
  , panelRef
  , settingsButtonRef
  , pictureRef
  , targetRef
  ) where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Foreign (Foreign)
import Graphics.Canvas (ImageData)
import Halogen as H
import Halogen.Subscription as HS
import Puregrain.Web.Download (Format, extension)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Prepare (Background, Placement, backgroundShows, white)
import Puregrain.Web.Save (fileName)
import Puregrain.Web.Settings (Settings)
import Puregrain.Web.Status (Run)
import Puregrain.Web.Theme (Theme)
import Web.Event.Event (Event)
import Web.HTML.Event.DragEvent (DragEvent)
import Web.UIEvent.KeyboardEvent (KeyboardEvent)
import Web.UIEvent.MouseEvent (MouseEvent)
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
-- | drag of files has entered (`Puregrain.Web.Drag`). `format` is the
-- | download's format chosen last, and `formatsOpen` whether the list of
-- | formats shows (`Puregrain.Web.Download`). `columnHidden` is the
-- | settings' column slid away (decision 29), and `panelOpen` the
-- | phone's settings panel open, which holds the runs until it closes.
-- | `resultLabel` names the result shown, for screen readers, and
-- | `status` and `alert` are what their two live regions say (decision
-- | 33): the run's milestones, and errors at once.
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
  , format :: Format
  , formatsOpen :: Boolean
  , theme :: Theme
  , libraryVersion :: String
  , columnHidden :: Boolean
  , panelOpen :: Boolean
  , resultLabel :: String
  , status :: Said
  , alert :: Said
  }

-- | What a live region says, and how many times it has spoken: the same
-- | words said again must still change the region, or screen readers
-- | don't repeat them.
type Said = { text :: String, times :: Int }

data Action
  = Initialize
  | Resized
  | ThemeToggled
  | ColumnToggled
  | PanelOpened
  | PanelClosed
  | HistoryPopped
  | SkippedToSettings MouseEvent
  | SkippedToPicture MouseEvent
  | PageKey KeyboardEvent
  | PageClicked Event
  | FileChosen Event
  | DragEntered DragEvent
  | DragLeft DragEvent
  | DragOver DragEvent
  | Dropped DragEvent
  | ZoomChosen String
  | ViewKey KeyboardEvent
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
  | SplitTo Int
  | DownloadClicked
  | FormatsToggled
  | FormatChosen Format

-- | A download's name (`Puregrain.Web.Save.fileName`): the picture's
-- | name and the settings; `fit` when the picture was fitted to a
-- | machine's screen, and the background when it shows in the result and
-- | isn't white; the format's extension.
downloadName :: State -> { picture :: Picture, prepared :: Prepared } -> Format -> String
downloadName s l format =
  fileName l.picture.name s.settings
    { fitted: isJust l.prepared.fitted
    , background:
        if backgroundShows l.picture.transparent l.prepared.fitted && s.background /= white then Just s.background
        else Nothing
    }
    (extension format)

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

-- | The settings' file chooser, which Ctrl+O opens.
chooserRef :: H.RefLabel
chooserRef = H.RefLabel "chooser"

-- | The download's box, and its ▾ button, which shows the list of formats.
downloadsRef :: H.RefLabel
downloadsRef = H.RefLabel "downloads"

formatsRef :: H.RefLabel
formatsRef = H.RefLabel "formats"

-- | The settings' column, which is the phone's panel, and the header's
-- | button that opens the panel.
panelRef :: H.RefLabel
panelRef = H.RefLabel "panel"

settingsButtonRef :: H.RefLabel
settingsButtonRef = H.RefLabel "settings-button"

-- | The picture area, where "Skip to the picture" goes.
pictureRef :: H.RefLabel
pictureRef = H.RefLabel "picture"

-- | The target that's chosen, where the focus goes after the first
-- | picture.
targetRef :: H.RefLabel
targetRef = H.RefLabel "target"
