-- | The web UI's component (web/ROADMAP.md): choose a picture or drop
-- | one, choose the settings, for any screen or a machine's, see the
-- | result, dithered in a worker with progress and cancelling, over the
-- | original at whole-number zoom, split by a slider, and save it as a
-- | PNG, or as the machine's own files. Its state and actions are in
-- | `Puregrain.Web.State`; its parts are drawn by `Puregrain.Web.View.*`.
module Puregrain.Web.App (component) where

import Prelude

import Control.Monad.Except (runExcept)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..), isJust)
import Effect (Effect)
import Effect.Aff (try)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Effect.Exception (message)
import Graphics.Canvas (imageDataBuffer)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.Event (eventListener)
import Halogen.Subscription as HS
import Puregrain.Web.Estimate (clock, next)
import Puregrain.Web.Message (Reply(..), describe, jobMessage, readReply)
import Puregrain.Web.Page (setTheme)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Picture as Picture
import Puregrain.Web.Pixels (copyPixels, toImageData, transferable)
import Puregrain.Web.Prepare (Background, backgroundFromHex, backgroundShows, fitOnto, flatten, placementOn, screenToFit, white)
import Puregrain.Web.Save (fileName, saveBytes, savePng, tapeName)
import Puregrain.Web.Screen (pixelRatio)
import Puregrain.Web.Settings (Colors(..), Settings, Target(..), allKernels, allMachines, allPalettes, chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, initial, isOriginal, kernelId, machineId, machinePaletteId, machinePalettesOf, paletteId)
import Puregrain.Web.State (Action(..), Input, Load(..), Prepared, Run(..), State, originalRef, resultRef)
import Puregrain.Web.Text (texts)
import Puregrain.Web.Theme (themeName, toggled)
import Puregrain.Web.View.Column (column)
import Puregrain.Web.View.Footer (footer)
import Puregrain.Web.View.Header (header)
import Puregrain.Web.View.Stage (stage)
import Web.Event.Event (EventType(..))
import Web.Event.Event as Event
import Web.File.File (File)
import Web.File.File as File
import Web.File.FileList as FileList
import Web.HTML (window)
import Web.HTML.Event.DataTransfer as DataTransfer
import Web.HTML.Event.DragEvent as DragEvent
import Web.HTML.HTMLInputElement as HTMLInputElement
import Web.HTML.Window as Window
import Web.Worker.MessageEvent (data_)
import Web.Worker.Worker as Worker

component :: forall q o m. MonadAff m => H.Component q Input o m
component = H.mkComponent
  { initialState: \input ->
      { load: NoPicture
      , loads: 0
      , zoom: 1
      , pixelRatio: 1.0
      , split: 0
      , fit: false
      , background: white
      , settings: initial
      , typed: { threshold: 128, levels: 2 }
      , run: Idle
      , runs: 0
      , worker: Nothing
      , listener: Nothing
      , theme: input.theme
      , libraryVersion: input.libraryVersion
      }
  , render
  , eval: H.mkEval H.defaultEval { handleAction = handleAction, initialize = Just Initialize }
  }

-- | The page (decision 29): the header, the settings' column beside the
-- | picture and its bar, the footer.
render :: forall m. State -> H.ComponentHTML Action () m
render state =
  -- The whole page takes a dropped file, so that a drop beside the
  -- picture doesn't make the browser open the file instead.
  HH.div [ HP.class_ (H.ClassName "app"), HE.onDragOver DragOver, HE.onDrop Dropped ]
    [ header state.theme
    , HH.div [ HP.class_ (H.ClassName "work") ]
        [ HH.aside [ HP.class_ (H.ClassName "column"), HP.attr (H.AttrName "aria-label") texts.settingsLabel ] (column state)
        , HH.main [ HP.class_ (H.ClassName "stage"), HP.attr (H.AttrName "aria-label") texts.pictureLabel ] (stage state)
        ]
    , footer state.libraryVersion
    ]

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
  ThemeToggled -> do
    theme <- H.gets (toggled <<< _.theme)
    liftEffect (setTheme (themeName theme))
    H.modify_ _ { theme = theme }
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
  TargetChosen value -> do
    let
      target =
        if value == "any" then Just AnyScreen
        else Machine <$> Array.find (\m -> machineId m == value) allMachines
    for_ target \t -> change (chooseTarget t)
  FitChosen fit -> do
    old <- H.gets _.fit
    when (fit /= old) do
      H.modify_ _ { fit = fit }
      refresh
  BackgroundChosen value ->
    for_ (backgroundFromHex value) \c -> do
      old <- H.gets _.background
      when (c /= old) do
        H.modify_ _ { background = c }
        refresh
  ColorsChosen value -> do
    s <- H.get
    let
      colors = case value of
        "original" -> Just Original
        "threshold" -> Just (Threshold s.typed.threshold)
        "levels" -> Just (Levels s.typed.levels)
        name -> case s.settings.target of
          AnyScreen -> Palette <$> Array.find (\p -> paletteId p == name) allPalettes
          Machine m -> MachineColors <$> Array.find (\p -> machinePaletteId p == name) (machinePalettesOf m)
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
  FromWorker id reply -> do
    s <- H.get
    when (id == s.runs) do
      case runExcept (readReply reply) of
        Left errors -> finish (RunFailed (describe errors))
        Right (Progress p) -> do
          t <- liftEffect clock
          H.modify_ \now -> case now.run of
            Running r -> now { run = Running r { done = p.done, total = p.total, left = next r.left { elapsed: t - r.started, done: p.done, total: p.total } } }
            _ -> now
        Right (Failure reason) -> finish (RunFailed reason)
        Right (Done result) -> case s.load of
          Loaded { prepared } -> do
            image <- liftEffect (toImageData result.pixels prepared.width prepared.height)
            -- Drawn while its canvas is still hidden, then shown.
            canvas <- H.getHTMLElementRef resultRef
            for_ canvas \element -> liftEffect (Picture.draw element image)
            finish (Finished { image, files: result.files, saveFailed: false })
          _ -> pure unit
  SplitMoved value -> do
    s <- H.get
    case s.load, Int.fromString value of
      Loaded { prepared }, Just split -> H.modify_ _ { split = clamp 0 prepared.width split }
      _, _ -> pure unit
  Save -> do
    s <- H.get
    canvas <- H.getHTMLElementRef resultRef
    case s.load, s.run, canvas of
      Loaded l, Finished _, Just element -> do
        saved <- liftAff (savePng element (fileName l.picture.name s.settings (nameParts s l) "png"))
        -- Unless another run has started meanwhile (`runs` counts on).
        H.modify_ \now -> case now.run of
          Finished r | now.runs == s.runs -> now { run = Finished r { saveFailed = not saved } }
          _ -> now
      _, _, _ -> pure unit
  SaveFile format -> do
    s <- H.get
    case s.load, s.run of
      Loaded l, Finished r ->
        for_ (Array.find (\f -> f.format == format) r.files) \f ->
          liftEffect (saveBytes f.bytes (fileName l.picture.name s.settings (nameParts s l) format))
      _, _ -> pure unit
  where
  readPixelRatio = do
    ratio <- liftEffect pixelRatio
    H.modify_ _ { pixelRatio = ratio }
  finish run = do
    stopWorker
    H.modify_ _ { run = run }

-- | What a download's name says about the preparation: `fit` when the
-- | picture was fitted, and the background when it shows and isn't white.
nameParts :: State -> { picture :: Picture, prepared :: Prepared } -> { fitted :: Boolean, background :: Maybe Background }
nameParts s l =
  { fitted: isJust l.prepared.fitted
  , background:
      if backgroundShows l.picture.transparent l.prepared.fitted && s.background /= white then Just s.background
      else Nothing
  }

-- | A change of the settings; a real change restarts the dithering, and
-- | a new target prepares the picture again, as it may fit it.
change :: forall o m. MonadAff m => (Settings -> Settings) -> H.HalogenM State Action () o m Unit
change f = do
  old <- H.gets _.settings
  let new = f old
  when (new /= old) do
    H.modify_ _ { settings = new }
    if new.target /= old.target then refresh else restart

-- | The picture as it's shown and dithered (decisions 22 and 27): put
-- | onto the background, if it has transparency, and fitted to a
-- | machine's screen, if asked.
prepare :: Picture -> Target -> Boolean -> Background -> Effect Prepared
prepare p target fit background = do
  opaque <- if p.transparent then flatten p.pixels background else pure p.pixels
  case screenToFit target fit size of
    Just screen -> do
      pixels <- fitOnto opaque size screen background
      image <- toImageData pixels screen.width screen.height
      pure { width: screen.width, height: screen.height, image, fitted: Just { screen, placement: placementOn screen size } }
    Nothing -> do
      image <- toImageData opaque p.width p.height
      pure { width: p.width, height: p.height, image, fitted: Nothing }
  where
  size = { width: p.width, height: p.height }

-- | Prepares the loaded picture again, for a new target, fit or
-- | background: shows it as the original (the split back in the middle
-- | when its size changed), and dithers it afresh.
refresh :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
refresh = do
  s <- H.get
  case s.load of
    Loaded l -> do
      stopWorker
      prepared <- liftEffect (prepare l.picture s.settings.target s.fit s.background)
      let resized = prepared.width /= l.prepared.width || prepared.height /= l.prepared.height
      H.modify_ _ { load = Loaded { picture: l.picture, prepared }, split = if resized then prepared.width / 2 else s.split, run = Idle }
      drawOriginal prepared
      restart
    _ -> pure unit

-- | Draws the prepared picture onto the original's canvas, once the state
-- | change has rendered it at its size.
drawOriginal :: forall o m. MonadAff m => Prepared -> H.HalogenM State Action () o m Unit
drawOriginal prepared = do
  canvas <- H.getHTMLElementRef originalRef
  for_ canvas \element -> liftEffect (Picture.draw element prepared.image)

-- | Ends the run, if any, and starts a new one for the picture and the
-- | settings, unless there's nothing to dither.
restart :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
restart = do
  stopWorker
  s <- H.get
  case s.load of
    Loaded l | not (isOriginal s.settings) -> startRun l s.settings
    _ -> H.modify_ _ { run = Idle }

-- | A new worker, given the settings, the size and a copy of the prepared
-- | picture's pixels; its answers come back as `FromWorker`, with this
-- | run's number.
startRun :: forall o m. MonadAff m => { picture :: Picture, prepared :: Prepared } -> Settings -> H.HalogenM State Action () o m Unit
startRun { picture: p, prepared } settings = do
  s <- H.get
  for_ s.listener \listener -> do
    let id = s.runs
    worker <- liftEffect (Worker.new "worker.js" Worker.defaultWorkerOptions)
    liftEffect (Worker.onMessage (\event -> HS.notify listener (FromWorker id (data_ event))) worker)
    copy <- liftEffect (copyPixels (imageDataBuffer prepared.image))
    let job = { settings, width: prepared.width, height: prepared.height, pixels: copy, tapeName: tapeName p.name }
    started <- liftEffect clock
    liftEffect (Worker.postMessage' (jobMessage job) [ transferable copy ] worker)
    H.modify_ _ { worker = Just worker, run = Running { done: 0, total: prepared.height, started, left: Nothing } }

-- | Ends the running worker, if any. `runs` counts on, so that an answer
-- | it had already sent is dropped.
stopWorker :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
stopWorker = do
  s <- H.get
  for_ s.worker (liftEffect <<< Worker.terminate)
  H.modify_ _ { worker = Nothing, runs = s.runs + 1 }

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
        s <- H.get
        prepared <- liftEffect (prepare p s.settings.target s.fit s.background)
        H.modify_ _ { load = Loaded { picture: p, prepared }, split = prepared.width / 2 }
        -- The state change rendered the canvases; draw, and dither.
        drawOriginal prepared
        restart
