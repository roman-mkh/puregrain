-- | The web UI's component. For now (phase 2 of web/ROADMAP.md): choose
-- | a picture or drop one, and see it at whole-number zoom.
module Puregrain.Web.App (component) where

import Prelude

import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Effect.Aff (try)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (message)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.Event (eventListener)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Picture as Picture
import Puregrain.Web.Screen (pixelRatio)
import Puregrain.Web.Text (texts)
import Puregrain.Web.Zoom (cssSize, zooms)
import Web.Event.Event (Event, EventType(..))
import Web.Event.Event as Event
import Web.File.File (File)
import Web.File.File as File
import Web.File.FileList as FileList
import Web.HTML (window)
import Web.HTML.Event.DataTransfer as DataTransfer
import Web.HTML.Event.DragEvent (DragEvent)
import Web.HTML.Event.DragEvent as DragEvent
import Web.HTML.HTMLInputElement as HTMLInputElement
import Web.HTML.Window as Window

-- | The picture: none yet, being loaded, failed to load, or loaded.
data Load
  = NoPicture
  | Loading String
  | Failed { name :: String, reason :: String }
  | Loaded Picture

-- | `loads` counts the loads started, so that a slow load's result is
-- | dropped when another file was chosen meanwhile.
type State =
  { load :: Load
  , loads :: Int
  , zoom :: Int
  , pixelRatio :: Number
  }

data Action
  = Initialize
  | Resized
  | FileChosen Event
  | DragOver DragEvent
  | Dropped DragEvent
  | ZoomChosen String

canvasRef :: H.RefLabel
canvasRef = H.RefLabel "picture"

component :: forall q i o m. MonadAff m => H.Component q i o m
component = H.mkComponent
  { initialState: const { load: NoPicture, loads: 0, zoom: 1, pixelRatio: 1.0 }
  , render
  , eval: H.mkEval H.defaultEval { handleAction = handleAction, initialize = Just Initialize }
  }

render :: forall m. State -> H.ComponentHTML Action () m
render state =
  -- The whole page takes a dropped file, so that a drop beside the input
  -- doesn't make the browser open the file instead.
  HH.main [ HP.class_ (H.ClassName "container"), HE.onDragOver DragOver, HE.onDrop Dropped ]
    ( [ HH.h1_ [ HH.text texts.title ]
      , HH.p_ [ HH.text texts.choose ]
      , HH.input [ HP.type_ HP.InputFile, HP.attr (H.AttrName "accept") "image/*", HE.onChange FileChosen ]
      ] <> picture state
    )

picture :: forall m. State -> Array (H.ComponentHTML Action () m)
picture state = case state.load of
  NoPicture -> []
  Loading name -> [ HH.p_ [ HH.text (texts.loading name) ] ]
  Failed failure -> [ HH.p_ [ HH.text (texts.failed failure) ] ]
  Loaded p ->
    let
      size = cssSize state.pixelRatio state.zoom { width: p.width, height: p.height }
    in
      [ HH.p_ [ HH.text (texts.loaded { name: p.name, width: p.width, height: p.height }) ]
      , HH.label_
          [ HH.text texts.zoom
          , HH.select [ HE.onValueChange ZoomChosen ] (map (zoomOption state.zoom) zooms)
          ]
      , HH.div [ HP.class_ (H.ClassName "view") ]
          [ HH.canvas
              [ HP.ref canvasRef
              , HP.class_ (H.ClassName "picture")
              , HP.width p.width
              , HP.height p.height
              , HP.style ("width: " <> show size.width <> "px; height: " <> show size.height <> "px")
              ]
          ]
      ]

zoomOption :: forall m. Int -> Int -> H.ComponentHTML Action () m
zoomOption current zoom =
  HH.option [ HP.value (show zoom), HP.selected (zoom == current) ] [ HH.text (texts.zoomLevel zoom) ]

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action () o m Unit
handleAction = case _ of
  Initialize -> do
    readPixelRatio
    -- The browser's own zoom changes the pixel ratio, and fires "resize".
    win <- liftEffect window
    void (H.subscribe (eventListener (EventType "resize") (Window.toEventTarget win) (const (Just Resized))))
  Resized -> readPixelRatio
  FileChosen event ->
    for_ (Event.target event >>= HTMLInputElement.fromEventTarget) \input -> do
      files <- liftEffect (HTMLInputElement.files input)
      for_ (files >>= FileList.item 0) loadFile
  DragOver event ->
    -- Without this, the browser doesn't let a file be dropped here.
    liftEffect (Event.preventDefault (DragEvent.toEvent event))
  Dropped event -> do
    liftEffect (Event.preventDefault (DragEvent.toEvent event))
    for_ (DataTransfer.files (DragEvent.dataTransfer event) >>= FileList.item 0) loadFile
  ZoomChosen value -> for_ (Int.fromString value) \zoom -> H.modify_ _ { zoom = zoom }
  where
  readPixelRatio = do
    ratio <- liftEffect pixelRatio
    H.modify_ _ { pixelRatio = ratio }

loadFile :: forall o m. MonadAff m => File -> H.HalogenM State Action () o m Unit
loadFile file = do
  started <- H.modify \s -> s { load = Loading (File.name file), loads = s.loads + 1 }
  result <- liftAff (try (Picture.load file))
  latest <- H.gets _.loads
  when (latest == started.loads) do
    case result of
      Left err -> H.modify_ _ { load = Failed { name: File.name file, reason: message err } }
      Right p -> do
        H.modify_ _ { load = Loaded p }
        -- The state change rendered the canvas; now it gets the pixels.
        canvas <- H.getHTMLElementRef canvasRef
        for_ canvas \element -> liftEffect (Picture.draw element p.pixels)
