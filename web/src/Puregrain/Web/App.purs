-- | The web UI's component. For now (phase 3 of web/ROADMAP.md): choose
-- | a picture or drop one, choose the settings, and see the result,
-- | dithered in a worker with progress and cancelling, at whole-number
-- | zoom.
module Puregrain.Web.App (component) where

import Prelude

import Control.Monad.Except (runExcept)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Effect.Aff (try)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (message)
import Foreign (Foreign)
import Graphics.Canvas (ImageData, imageDataBuffer)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.Event (eventListener)
import Halogen.Subscription as HS
import Puregrain.Web.Message (Reply(..), describe, jobMessage, readReply)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Picture as Picture
import Puregrain.Web.Pixels (copyPixels, toImageData, transferable)
import Puregrain.Web.Screen (pixelRatio)
import Puregrain.Web.Settings (Colors(..), Settings, allKernels, allPalettes, bayerAllowed, bayerSides, chooseBayer, chooseColors, chooseGray, chooseKernel, initial, isOriginal, kernelId, paletteId)
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
import Web.Worker.MessageEvent (data_)
import Web.Worker.Worker (Worker)
import Web.Worker.Worker as Worker

-- | The picture: none yet, being loaded, failed to load, or loaded.
data Load
  = NoPicture
  | Loading String
  | Failed { name :: String, reason :: String }
  | Loaded Picture

-- | The dithering: none, running (rows done of all), finished with the
-- | result, cancelled, or failed.
data Run
  = Idle
  | Running { done :: Int, total :: Int }
  | Finished ImageData
  | Cancelled
  | RunFailed String

-- | `loads` and `runs` count the loads and the runs started, so that a
-- | slow load's result, or an answer from a worker already ended, is
-- | dropped. `typed` keeps the threshold and the number of levels last
-- | typed, for when those colors are chosen again.
type State =
  { load :: Load
  , loads :: Int
  , zoom :: Int
  , pixelRatio :: Number
  , settings :: Settings
  , typed :: { threshold :: Int, levels :: Int }
  , run :: Run
  , runs :: Int
  , worker :: Maybe Worker
  , listener :: Maybe (HS.Listener Action)
  }

data Action
  = Initialize
  | Resized
  | FileChosen Event
  | DragOver DragEvent
  | Dropped DragEvent
  | ZoomChosen String
  | ColorsChosen String
  | ThresholdTyped String
  | LevelsTyped String
  | KernelChosen String
  | BayerChosen String
  | GrayChosen Boolean
  | Cancel
  | FromWorker Int Foreign

canvasRef :: H.RefLabel
canvasRef = H.RefLabel "picture"

component :: forall q i o m. MonadAff m => H.Component q i o m
component = H.mkComponent
  { initialState: const
      { load: NoPicture
      , loads: 0
      , zoom: 1
      , pixelRatio: 1.0
      , settings: initial
      , typed: { threshold: 128, levels: 2 }
      , run: Idle
      , runs: 0
      , worker: Nothing
      , listener: Nothing
      }
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
      -- The parts whose elements come and go sit in fixed containers, so
      -- the canvas keeps its place among its siblings: Halogen matches
      -- unkeyed children by position, and would otherwise rebuild the
      -- canvas, blank, whenever the progress bar appears or goes.
      [ HH.p_ [ HH.text (texts.loaded { name: p.name, width: p.width, height: p.height }) ]
      , HH.div [ HP.class_ (H.ClassName "settings") ] (settingsForm state.settings)
      , HH.div [ HP.class_ (H.ClassName "status") ] (runStatus state.run)
      ]
        <>
          [ HH.label_
              [ HH.text texts.zoom
              , HH.select [ HE.onValueChange ZoomChosen ]
                  (map (\z -> option (show z) (texts.zoomLevel z) (z == state.zoom)) zooms)
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

settingsForm :: forall m. Settings -> Array (H.ComponentHTML Action () m)
settingsForm s =
  [ HH.label_
      [ HH.text texts.colors
      , HH.select [ HE.onValueChange ColorsChosen ]
          ( [ option "original" texts.colorsOriginal (s.colors == Original)
            , option "threshold" texts.colorsThreshold (isThreshold s.colors)
            , option "levels" texts.colorsLevels (isLevels s.colors)
            ]
              <> map (\p -> option (paletteId p) (texts.palette p) (s.colors == Palette p)) allPalettes
          )
      ]
  ]
    <> amount s.colors
    <>
      [ HH.label_
          [ HH.text texts.kernel
          , HH.select [ HE.onValueChange KernelChosen ]
              (map (\k -> option (kernelId k) (texts.kernelName k) (k == s.kernel)) allKernels)
          ]
      , HH.label_
          [ HH.text texts.bayer
          , HH.select [ HE.onValueChange BayerChosen, HP.disabled (not (bayerAllowed s.colors)) ]
              ( [ option "none" texts.bayerOff (s.bayer == Nothing) ]
                  <> map (\side -> option (show side) (texts.bayerSide side) (s.bayer == Just side)) bayerSides
              )
          ]
      ]
    <> (if bayerAllowed s.colors then [] else [ HH.small_ [ HH.text texts.bayerNeedsLevels ] ])
    <>
      [ HH.label_
          [ HH.input [ HP.type_ HP.InputCheckbox, HP.checked s.gray, HE.onChecked GrayChosen ]
          , HH.text texts.gray
          ]
      ]
  where
  isThreshold = case _ of
    Threshold _ -> true
    _ -> false
  isLevels = case _ of
    Levels _ -> true
    _ -> false
  amount = case _ of
    Threshold t -> [ number texts.thresholdValue 0 255 t ThresholdTyped ]
    Levels n -> [ number texts.levelsValue 2 256 n LevelsTyped ]
    _ -> []
  number label low high value action =
    HH.label_
      [ HH.text label
      , HH.input
          [ HP.type_ HP.InputNumber
          , HP.min (toNumber low)
          , HP.max (toNumber high)
          , HP.value (show value)
          , HE.onValueInput action
          ]
      ]

runStatus :: forall m. Run -> Array (H.ComponentHTML Action () m)
runStatus = case _ of
  Idle -> []
  Running r ->
    [ HH.p_ [ HH.text (texts.dithering r) ]
    , HH.progress [ HP.max (toNumber r.total), HP.value (toNumber r.done) ] []
    , HH.button [ HE.onClick (const Cancel) ] [ HH.text texts.cancel ]
    ]
  Finished _ -> []
  Cancelled -> [ HH.p_ [ HH.text texts.cancelled ] ]
  RunFailed reason -> [ HH.p_ [ HH.text (texts.ditherFailed reason) ] ]

option :: forall m. String -> String -> Boolean -> H.ComponentHTML Action () m
option value label selected = HH.option [ HP.value value, HP.selected selected ] [ HH.text label ]

handleAction :: forall o m. MonadAff m => Action -> H.HalogenM State Action () o m Unit
handleAction = case _ of
  Initialize -> do
    { emitter, listener } <- liftEffect HS.create
    void (H.subscribe emitter)
    H.modify_ _ { listener = Just listener }
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
  ColorsChosen value -> do
    s <- H.get
    let
      colors = case value of
        "original" -> Just Original
        "threshold" -> Just (Threshold s.typed.threshold)
        "levels" -> Just (Levels s.typed.levels)
        name -> Palette <$> Array.find (\p -> paletteId p == name) allPalettes
    for_ colors \c -> change (chooseColors c)
  ThresholdTyped value ->
    for_ (Int.fromString value) \t -> when (t >= 0 && t <= 255) do
      H.modify_ \s -> s { typed = s.typed { threshold = t } }
      change (chooseColors (Threshold t))
  LevelsTyped value ->
    for_ (Int.fromString value) \n -> when (n >= 2 && n <= 256) do
      H.modify_ \s -> s { typed = s.typed { levels = n } }
      change (chooseColors (Levels n))
  KernelChosen value ->
    for_ (Array.find (\k -> kernelId k == value) allKernels) \k -> change (chooseKernel k)
  BayerChosen value ->
    if value == "none" then change (chooseBayer Nothing)
    else for_ (Int.fromString value) \side -> change (chooseBayer (Just side))
  GrayChosen gray -> change (chooseGray gray)
  Cancel -> do
    stopWorker
    H.modify_ _ { run = Cancelled }
    showPixels
  FromWorker id reply -> do
    s <- H.get
    when (id == s.runs) do
      case runExcept (readReply reply) of
        Left errors -> finish (RunFailed (describe errors))
        Right (Progress p) -> H.modify_ _ { run = Running p }
        Right (Failure reason) -> finish (RunFailed reason)
        Right (Done pixels) -> case s.load of
          Loaded p -> do
            image <- liftEffect (toImageData pixels p.width p.height)
            finish (Finished image)
          _ -> pure unit
  where
  readPixelRatio = do
    ratio <- liftEffect pixelRatio
    H.modify_ _ { pixelRatio = ratio }
  finish run = do
    stopWorker
    H.modify_ _ { run = run }
    showPixels

-- | A change of the settings; a real change restarts the dithering.
change :: forall o m. MonadAff m => (Settings -> Settings) -> H.HalogenM State Action () o m Unit
change f = do
  old <- H.gets _.settings
  let new = f old
  when (new /= old) do
    H.modify_ _ { settings = new }
    restart

-- | Ends the run, if any, and starts a new one for the picture and the
-- | settings, unless there's nothing to dither.
restart :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
restart = do
  stopWorker
  s <- H.get
  case s.load of
    Loaded p | not (isOriginal s.settings) -> startRun p s.settings
    _ -> H.modify_ _ { run = Idle }
  showPixels

-- | A new worker, given the settings, the size and a copy of the picture's
-- | pixels; its answers come back as `FromWorker`, with this run's number.
startRun :: forall o m. MonadAff m => Picture -> Settings -> H.HalogenM State Action () o m Unit
startRun p settings = do
  s <- H.get
  for_ s.listener \listener -> do
    let id = s.runs
    worker <- liftEffect (Worker.new "worker.js" Worker.defaultWorkerOptions)
    liftEffect (Worker.onMessage (\event -> HS.notify listener (FromWorker id (data_ event))) worker)
    copy <- liftEffect (copyPixels (imageDataBuffer p.pixels))
    liftEffect (Worker.postMessage' (jobMessage { settings, width: p.width, height: p.height, pixels: copy }) [ transferable copy ] worker)
    H.modify_ _ { worker = Just worker, run = Running { done: 0, total: p.height } }

-- | Ends the running worker, if any. `runs` counts on, so that an answer
-- | it had already sent is dropped.
stopWorker :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
stopWorker = do
  s <- H.get
  for_ s.worker (liftEffect <<< Worker.terminate)
  H.modify_ _ { worker = Nothing, runs = s.runs + 1 }

-- | Draws what the view shows: the result once there is one, the original
-- | otherwise, also while a run is going.
showPixels :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
showPixels = do
  s <- H.get
  case s.load of
    Loaded p -> do
      canvas <- H.getHTMLElementRef canvasRef
      let
        pixels = case s.run of
          Finished image -> image
          _ -> p.pixels
      for_ canvas \element -> liftEffect (Picture.draw element pixels)
    _ -> pure unit

loadFile :: forall o m. MonadAff m => File -> H.HalogenM State Action () o m Unit
loadFile file = do
  stopWorker
  started <- H.modify \s -> s { load = Loading (File.name file), loads = s.loads + 1, run = Idle }
  result <- liftAff (try (Picture.load file))
  latest <- H.gets _.loads
  when (latest == started.loads) do
    case result of
      Left err -> H.modify_ _ { load = Failed { name: File.name file, reason: message err } }
      Right p -> do
        H.modify_ _ { load = Loaded p }
        -- The state change rendered the canvas; dither, and draw.
        restart
