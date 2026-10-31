-- | The web UI's component (web/ROADMAP.md): choose a picture or drop
-- | one, choose the settings, for any screen or a machine's, see the
-- | result, dithered in a worker with progress and cancelling, over the
-- | original at whole-number zoom, split by a handle, and save it as a
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
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Aff (delay, try)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (liftEffect)
import Graphics.Canvas (imageDataBuffer)
import Halogen as H
import Halogen.HTML as HH
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
import Halogen.Query.Event (eventListener)
import Halogen.Subscription as HS
import Puregrain.Web.Drag (DragStep(..), counted, holdsFiles)
import Puregrain.Web.Estimate (clock, next)
import Puregrain.Web.Message (Reply(..), describe, jobMessage, readReply)
import Puregrain.Web.Page (setTheme)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Picture as Picture
import Puregrain.Web.Pixels (copyPixels, toImageData, transferable)
import Puregrain.Web.Pointer (across, capture, mainButton, pointerId, pressed)
import Puregrain.Web.Prepare (Background, backgroundFromHex, backgroundShows, fitOnto, flatten, placementOn, screenToFit, white)
import Puregrain.Web.Save (fileName, saveBytes, savePng, tapeName)
import Puregrain.Web.Screen (pixelRatio)
import Puregrain.Web.Settings (Colors(..), Settings, Target(..), allKernels, allMachines, allPalettes, chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, initial, isOriginal, kernelId, machineId, machinePaletteId, machinePalettesOf, paletteId)
import Puregrain.Web.Split (columnAt, grabAt, keyed)
import Puregrain.Web.State (Action(..), Input, Load(..), Prepared, State, handleRef, layersRef, originalRef, resultRef)
import Puregrain.Web.Status (Run(..), progressDelay, resultShows)
import Puregrain.Web.Text (texts)
import Puregrain.Web.Theme (themeName, toggled)
import Puregrain.Web.View.Column (column)
import Puregrain.Web.View.Footer (footer)
import Puregrain.Web.View.Header (header)
import Puregrain.Web.View.Icon as Icon
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
import Web.UIEvent.KeyboardEvent as KE
import Web.Worker.MessageEvent (data_)
import Web.Worker.Worker as Worker

component :: forall q o m. MonadAff m => H.Component q Input o m
component = H.mkComponent
  { initialState: \input ->
      { load: NoPicture
      , loads: 0
      , loading: Nothing
      , notAPicture: Nothing
      , zoom: 1
      , pixelRatio: 1.0
      , split: 0
      , splitDrag: Nothing
      , fit: false
      , background: white
      , settings: initial
      , typed: { threshold: 128, levels: 2 }
      , run: Idle
      , runs: 0
      , worker: Nothing
      , listener: Nothing
      , dragged: 0
      , theme: input.theme
      , libraryVersion: input.libraryVersion
      , columnHidden: false
      }
  , render
  , eval: H.mkEval H.defaultEval { handleAction = handleAction, initialize = Just Initialize }
  }

-- | The page (decision 29): the header, the settings' column beside the
-- | picture and its bar, the footer.
render :: forall m. State -> H.ComponentHTML Action () m
render state =
  -- The whole page takes a dropped file, so that a drop beside the
  -- picture doesn't make the browser open the file instead; and it
  -- counts what a drag of files enters and leaves, for the overlay.
  HH.div
    [ HP.class_ (H.ClassName "app")
    , HE.onDragEnter DragEntered
    , HE.onDragLeave DragLeft
    , HE.onDragOver DragOver
    , HE.onDrop Dropped
    ]
    [ header state.theme
    , HH.div [ HP.classes ([ H.ClassName "work" ] <> (if state.columnHidden then [ H.ClassName "column-hidden" ] else [])) ]
        -- The « / » tab on the column's edge (decision 29): it says
        -- whether the column is open, and which column it opens.
        [ HH.button
            [ HP.type_ HP.ButtonButton
            , HP.class_ (H.ClassName "column-tab")
            , HP.attr (H.AttrName "aria-expanded") (if state.columnHidden then "false" else "true")
            , HP.attr (H.AttrName "aria-controls") "settings"
            , HP.title (if state.columnHidden then texts.showSettings else texts.hideSettings)
            , HE.onClick (const ColumnToggled)
            ]
            [ if state.columnHidden then Icon.chevronsRight else Icon.chevronsLeft
            , HH.span [ HP.class_ (H.ClassName "sr-only") ] [ HH.text texts.settingsLabel ]
            ]
        , HH.aside [ HP.id "settings", HP.class_ (H.ClassName "column"), HP.attr (H.AttrName "aria-label") texts.settingsLabel ] (column state)
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
  ColumnToggled -> H.modify_ \s -> s { columnHidden = not s.columnHidden }
  FileChosen event ->
    for_ (Event.target event >>= HTMLInputElement.fromEventTarget) \input -> do
      files <- liftEffect (HTMLInputElement.files input)
      for_ (files >>= FileList.item 0) loadFile
  DragEntered event -> dragStep event Enter
  DragLeft event -> dragStep event Leave
  DragOver event ->
    -- Without this, the browser doesn't let a file be dropped here.
    liftEffect (Event.preventDefault (DragEvent.toEvent event))
  Dropped event -> do
    liftEffect (Event.preventDefault (DragEvent.toEvent event))
    H.modify_ \s -> s { dragged = counted s.dragged Drop }
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
  -- While the slider is dragged its value shows, and only its release
  -- starts a run (decision 31).
  ThresholdDragged value ->
    for_ (Int.fromString value) \t -> when (t >= 0 && t <= 255) do
      H.modify_ \s -> s { typed = s.typed { threshold = t } }
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
            -- Drawn over the result before it, or while its canvas is
            -- still hidden, then shown.
            canvas <- H.getHTMLElementRef resultRef
            for_ canvas \element -> liftEffect (Picture.draw element image)
            finish (Finished { files: result.files, saveFailed: false })
          _ -> pure unit
  -- The handle (decision 31): it follows the pointer that took hold of
  -- it, captured, so also outside it, until the pointer is released.
  SplitPressed event -> when (mainButton event) do
    s <- H.get
    layers <- H.getHTMLElementRef layersRef
    handle <- H.getHTMLElementRef handleRef
    case s.load, layers, handle of
      Loaded { prepared }, Just box, Just h -> do
        at <- liftEffect (across event box)
        liftEffect (capture h (pointerId event))
        H.modify_ _ { splitDrag = Just { pointer: pointerId event, grab: grabAt at s.split prepared.width } }
      _, _, _ -> pure unit
  SplitDragged event -> do
    s <- H.get
    case s.splitDrag, s.load of
      Just drag, Loaded { prepared } | drag.pointer == pointerId event ->
        -- A drag whose release went elsewhere ends at the next move.
        if not (pressed event) then H.modify_ _ { splitDrag = Nothing }
        else do
          layers <- H.getHTMLElementRef layersRef
          for_ layers \box -> do
            at <- liftEffect (across event box)
            let split = columnAt (at - drag.grab) prepared.width
            when (split /= s.split) (H.modify_ _ { split = split })
      _, _ -> pure unit
  SplitReleased event -> do
    drag <- H.gets _.splitDrag
    for_ drag \d -> when (d.pointer == pointerId event) (H.modify_ _ { splitDrag = Nothing })
  SplitKey event -> do
    s <- H.get
    case s.load of
      Loaded { prepared } -> do
        let key = { key: KE.key event, shift: KE.shiftKey event, modified: KE.ctrlKey event || KE.altKey event || KE.metaKey event }
        for_ (keyed key s.split prepared.width) \split -> do
          -- The key moves the handle only, without scrolling the page.
          liftEffect (Event.preventDefault (KE.toEvent event))
          H.modify_ _ { split = split }
      _ -> pure unit
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
  -- Only drags that hold files count (`Puregrain.Web.Drag`).
  dragStep event step =
    when (holdsFiles (DataTransfer.types (DragEvent.dataTransfer event))) do
      H.modify_ \s -> s { dragged = counted s.dragged step }

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
      H.modify_ _ { load = Loaded { picture: l.picture, prepared }, split = if resized then prepared.width / 2 else s.split, splitDrag = Nothing, run = Idle }
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
-- | settings, unless there's nothing to dither. A note on a file that
-- | wasn't a picture goes: this is the next action (decision 30 A).
restart :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
restart = do
  stopWorker
  H.modify_ _ { notAPicture = Nothing }
  s <- H.get
  case s.load of
    Loaded l | not (isOriginal s.settings) -> startRun l s.settings
    _ -> H.modify_ _ { run = Idle }

-- | A new worker, given the settings, the size and a copy of the prepared
-- | picture's pixels; its answers come back as `FromWorker`, with this
-- | run's number. The result before it stays on show, if it shows
-- | (`resultShows`); the progress shows after `progressDelay`, unless
-- | the run is over by then (decision 30 B).
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
    H.modify_ _
      { worker = Just worker
      , run = Running { done: 0, total: prepared.height, started, left: Nothing, progressShown: false, keepsPrevious: resultShows s.run }
      }
    void $ H.fork do
      liftAff (delay (Milliseconds progressDelay))
      now <- H.get
      case now.run of
        Running r | now.runs == id -> H.modify_ _ { run = Running r { progressShown = true } }
        _ -> pure unit

-- | Ends the running worker, if any. `runs` counts on, so that an answer
-- | it had already sent is dropped.
stopWorker :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
stopWorker = do
  s <- H.get
  for_ s.worker (liftEffect <<< Worker.terminate)
  H.modify_ _ { worker = Nothing, runs = s.runs + 1 }

-- | Loads a file chosen or dropped. The picture shown and its run stay
-- | until the new one has decoded, and stay for good if it can't be
-- | (decision 30 C); then a note says so, until the next action.
loadFile :: forall o m. MonadAff m => File -> H.HalogenM State Action () o m Unit
loadFile file = do
  started <- H.modify \s -> s { loading = Just (File.name file), notAPicture = Nothing, loads = s.loads + 1 }
  result <- liftAff (try (Picture.load file))
  latest <- H.gets _.loads
  when (latest == started.loads) do
    case result of
      Left _ -> H.modify_ _ { loading = Nothing, notAPicture = Just (File.name file) }
      Right p -> do
        stopWorker
        s <- H.get
        prepared <- liftEffect (prepare p s.settings.target s.fit s.background)
        H.modify_ _ { load = Loaded { picture: p, prepared }, loading = Nothing, split = prepared.width / 2, splitDrag = Nothing, run = Idle }
        -- The state change rendered the canvases; draw, and dither.
        drawOriginal prepared
        restart
