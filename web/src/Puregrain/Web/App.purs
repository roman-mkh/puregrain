-- | The web UI's component (web/ROADMAP.md): choose a picture or drop
-- | one, choose the settings, for any screen or a machine's, see the
-- | result, dithered in a worker with progress and cancelling, over the
-- | original at whole-number zoom, split by a handle, and save it as a
-- | PNG, or as the machine's own files. Its state and actions are in
-- | `Puregrain.Web.State`; its parts are drawn by `Puregrain.Web.View.*`.
module Puregrain.Web.App (component) where

import Prelude

import Control.Monad.Except (runExcept)
import Foreign (unsafeToForeign)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Int as Int
import Data.Maybe (Maybe(..))
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
import Puregrain.Web.Download (Format(..), buttonFormat, extension, formatsFor)
import Puregrain.Web.Drag (DragStep(..), counted, holdsFiles)
import Puregrain.Web.Estimate (clock, next)
import Puregrain.Web.Keys (FocusAfterLoad(..), Shortcut(..), focusAfterLoad, shortcut, zoomStep)
import Puregrain.Web.Message (Reply(..), describe, jobMessage, readReply)
import Puregrain.Web.Page (narrowScreen, setTheme)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Picture as Picture
import Puregrain.Web.Pixels (copyPixels, toImageData, transferable)
import Puregrain.Web.Pointer (across, capture, mainButton, pointerId, pressed)
import Puregrain.Web.Prepare (Background, backgroundFromHex, fitOnto, flatten, placementOn, screenToFit, white)
import Puregrain.Web.Save (saveBytes, savePng, tapeName)
import Puregrain.Web.Screen (pixelRatio)
import Puregrain.Web.Settings (Colors(..), Settings, Target(..), allKernels, allMachines, allPalettes, chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, initial, isOriginal, kernelId, machineId, machinePaletteId, machinePalettesOf, paletteId)
import Puregrain.Web.Split (columnAt, grabAt, keyed)
import Puregrain.Web.State (Action(..), Input, Load(..), Prepared, Said, State, chooserRef, downloadName, downloadsRef, formatsRef, handleRef, layersRef, originalRef, panelRef, pictureRef, resultRef, settingsButtonRef, targetRef)
import Puregrain.Web.Status (Run(..), held, progressDelay, resultShows)
import Puregrain.Web.Text (texts)
import Puregrain.Web.Theme (themeName, toggled)
import Puregrain.Web.View.Column (column)
import Puregrain.Web.View.Footer (footer)
import Puregrain.Web.View.Header (header)
import Puregrain.Web.View.Icon as Icon
import Puregrain.Web.View.Parts (inert)
import Puregrain.Web.View.Stage (stage)
import Puregrain.Web.Zoom (stepped)
import Web.DOM.Node as Node
import Web.Event.Event (EventType(..))
import Web.Event.Event as Event
import Web.File.File (File)
import Web.File.File as File
import Web.File.FileList as FileList
import Web.HTML (window)
import Web.HTML.Event.DataTransfer as DataTransfer
import Web.HTML.Event.DragEvent as DragEvent
import Web.HTML.HTMLElement as HTMLElement
import Web.HTML.HTMLInputElement as HTMLInputElement
import Web.HTML.History as History
import Web.HTML.Location as Location
import Web.HTML.Window as Window
import Web.UIEvent.KeyboardEvent as KE
import Web.UIEvent.MouseEvent as ME
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
      , format: Png
      , formatsOpen: false
      , theme: input.theme
      , libraryVersion: input.libraryVersion
      , columnHidden: false
      , panelOpen: false
      , resultLabel: ""
      , status: { text: "", times: 0 }
      , alert: { text: "", times: 0 }
      }
  , render
  , eval: H.mkEval H.defaultEval { handleAction = handleAction, initialize = Just Initialize }
  }

-- | The page (decision 29): the header, the settings' column beside the
-- | picture and its bar, the footer. On phones the column is a panel over
-- | the page, opened by the header's settings button; while it's open,
-- | the rest of the page is `inert`, and the panel a modal dialog. Before
-- | them the skip links, which the first Tab shows; after them the live
-- | regions for screen readers, outside every part that can turn inert
-- | (decision 33).
render :: forall m. State -> H.ComponentHTML Action () m
render state =
  -- The whole page takes a dropped file, so that a drop beside the
  -- picture doesn't make the browser open the file instead; and it
  -- counts what a drag of files enters and leaves, for the overlay.
  HH.div
    [ HP.classes ([ H.ClassName "app" ] <> (if state.panelOpen then [ H.ClassName "panel-open" ] else []))
    , HE.onDragEnter DragEntered
    , HE.onDragLeave DragLeft
    , HE.onDragOver DragOver
    , HE.onDrop Dropped
    ]
    [ HH.div [ HP.class_ (H.ClassName "skips"), inert state.panelOpen ]
        [ HH.a
            [ HP.href "#settings"
            , HP.classes [ H.ClassName "skip", H.ClassName "to-settings" ]
            , HP.prop (H.PropName "hidden") state.columnHidden
            , HE.onClick SkippedToSettings
            ]
            [ HH.text texts.skipToSettings ]
        , HH.a [ HP.href "#picture", HP.class_ (H.ClassName "skip"), HE.onClick SkippedToPicture ] [ HH.text texts.skipToPicture ]
        ]
    , header { theme: state.theme, settings: loaded, panelOpen: state.panelOpen }
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
            , inert state.panelOpen
            ]
            [ if state.columnHidden then Icon.chevronsRight else Icon.chevronsLeft
            , HH.span [ HP.class_ (H.ClassName "sr-only") ] [ HH.text texts.settingsLabel ]
            ]
        -- What `aside` means, as a `div`, which unlike an `aside` may also be
        -- a dialog: the phone's panel, while it's open.
        , HH.div
            ( [ HP.ref panelRef
              , HP.id "settings"
              , HP.class_ (H.ClassName "column")
              , HP.attr (H.AttrName "aria-label") texts.settingsLabel
              , HP.tabIndex (-1)
              ]
                <>
                  if state.panelOpen then [ HP.attr (H.AttrName "role") "dialog", HP.attr (H.AttrName "aria-modal") "true" ]
                  else [ HP.attr (H.AttrName "role") "complementary" ]
            )
            (column state)
        , HH.main
            [ HP.ref pictureRef
            , HP.id "picture"
            , HP.class_ (H.ClassName "stage")
            , HP.attr (H.AttrName "aria-label") texts.pictureLabel
            , HP.tabIndex (-1)
            , inert state.panelOpen
            ]
            (stage state)
        ]
    , footer state.libraryVersion state.panelOpen
    , HH.div [ HP.class_ (H.ClassName "sr-only"), HP.attr (H.AttrName "role") "status" ] [ HH.text (spoken state.status) ]
    , HH.div [ HP.class_ (H.ClassName "sr-only"), HP.attr (H.AttrName "role") "alert" ] [ HH.text (spoken state.alert) ]
    ]
  where
  -- A no-break space every other time, unheard: the same words again
  -- still change the region.
  spoken said = said.text <> (if said.times `mod` 2 == 1 then "\x00A0" else "")
  loaded = case state.load of
    Loaded _ -> true
    NoPicture -> false

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
    -- The shortcuts work anywhere on the page, and a click outside the
    -- list of formats closes it.
    void (H.subscribe (eventListener (EventType "keydown") (Window.toEventTarget win) (map PageKey <<< KE.fromEvent)))
    void (H.subscribe (eventListener (EventType "click") (Window.toEventTarget win) (Just <<< PageClicked)))
    -- Back, while the phone's panel is open, closes it (decision 34).
    void (H.subscribe (eventListener (EventType "popstate") (Window.toEventTarget win) (const (Just HistoryPopped))))
    -- The empty page's one thing to do, choosing a picture, has the focus
    -- from the start, so that Enter opens the file chooser; not on a
    -- phone, where the settings are hidden and the focus does nothing.
    narrow <- liftEffect narrowScreen
    unless narrow do
      chooser <- H.getHTMLElementRef chooserRef
      for_ chooser (liftEffect <<< HTMLElement.focus)
  Resized -> do
    readPixelRatio
    -- A phone turned sideways, a window widened: no panel any more.
    narrow <- liftEffect narrowScreen
    open <- H.gets _.panelOpen
    when (open && not narrow) (closePanel false)
  ThemeToggled -> do
    theme <- H.gets (toggled <<< _.theme)
    liftEffect (setTheme (themeName theme))
    H.modify_ _ { theme = theme }
  ColumnToggled -> H.modify_ \s -> s { columnHidden = not s.columnHidden }
  -- The phone's settings panel (decisions 29 and 34): it takes the focus,
  -- and adds a step to the browser's history, so that the back gesture
  -- closes it instead of leaving the page.
  PanelOpened -> do
    H.modify_ _ { panelOpen = true, formatsOpen = false }
    liftEffect do
      win <- window
      href <- Location.href =<< Window.location win
      History.pushState (unsafeToForeign { panel: true }) (History.DocumentTitle "") (History.URL href) =<< Window.history win
    panel <- H.getHTMLElementRef panelRef
    for_ panel (liftEffect <<< HTMLElement.focus)
  PanelClosed -> closePanel false
  HistoryPopped -> do
    open <- H.gets _.panelOpen
    when open (closePanel true)
  -- The shortcuts (decision 33, `Puregrain.Web.Keys`): Ctrl+O and Ctrl+S
  -- are taken over from the browser, Ctrl+S even with nothing to
  -- download yet, so that "Save page as" doesn't open over the page.
  -- The skip links move the focus, without changing the page's address.
  SkippedToSettings event -> skipTo event panelRef
  SkippedToPicture event -> skipTo event pictureRef
  PageKey event -> for_ (shortcut (keyOf event)) case _ of
    ChoosePicture -> do
      liftEffect (Event.preventDefault (KE.toEvent event))
      chooser <- H.getHTMLElementRef chooserRef
      for_ chooser (liftEffect <<< HTMLElement.click)
    DownloadNow -> do
      liftEffect (Event.preventDefault (KE.toEvent event))
      H.modify_ _ { formatsOpen = false }
      s <- H.get
      download (buttonFormat s.format (choicesOf s))
    -- The phone's panel first, then the list of formats, then the run.
    Escape -> do
      s <- H.get
      if s.panelOpen then do
        liftEffect (Event.preventDefault (KE.toEvent event))
        closePanel false
      else if s.formatsOpen then do
        liftEffect (Event.preventDefault (KE.toEvent event))
        closeFormats
      else case s.run of
        Running _ -> do
          liftEffect (Event.preventDefault (KE.toEvent event))
          cancel
        _ -> pure unit
  PageClicked event -> do
    open <- H.gets _.formatsOpen
    when open do
      box <- H.getHTMLElementRef downloadsRef
      inside <- case box, Event.target event >>= Node.fromEventTarget of
        Just b, Just node -> liftEffect (Node.contains (HTMLElement.toNode b) node)
        _, _ -> pure false
      unless inside (H.modify_ _ { formatsOpen = false })
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
  ViewKey event -> for_ (zoomStep (keyOf event)) \step -> do
    liftEffect (Event.preventDefault (KE.toEvent event))
    H.modify_ \s -> s { zoom = stepped step s.zoom }
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
  Cancel -> cancel
  FromWorker id reply -> do
    s <- H.get
    when (id == s.runs) do
      case runExcept (readReply reply) of
        Left errors -> failed (describe errors)
        Right (Progress p) -> do
          t <- liftEffect clock
          H.modify_ \now -> case now.run of
            Running r -> now { run = Running r { done = p.done, total = p.total, left = next r.left { elapsed: t - r.started, done: p.done, total: p.total } } }
            _ -> now
        Right (Failure reason) -> failed reason
        Right (Done result) -> case s.load of
          Loaded { prepared } -> do
            image <- liftEffect (toImageData result.pixels prepared.width prepared.height)
            -- Drawn over the result before it, or while its canvas is
            -- still hidden, then shown.
            canvas <- H.getHTMLElementRef resultRef
            for_ canvas \element -> liftEffect (Picture.draw element image)
            finish (Finished { files: result.files, saveFailed: false })
            H.modify_ \now -> now { resultLabel = texts.resultNamed now.settings }
            say (texts.done s.settings)
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
  -- The download (decision 31, `Puregrain.Web.Download`).
  DownloadClicked -> do
    s <- H.get
    download (buttonFormat s.format (choicesOf s))
  FormatsToggled -> H.modify_ \s -> s { formatsOpen = not s.formatsOpen }
  -- A format from the list: downloaded, and the button's from now on;
  -- one that isn't possible does nothing.
  FormatChosen format -> do
    s <- H.get
    when (Array.any (\c -> c.format == format && c.possible) (choicesOf s)) do
      H.modify_ _ { format = format }
      closeFormats
      download format
  where
  keyOf event =
    { key: KE.key event
    , code: KE.code event
    , ctrl: KE.ctrlKey event
    , meta: KE.metaKey event
    , alt: KE.altKey event
    , shift: KE.shiftKey event
    }
  cancel = do
    stopWorker
    H.modify_ _ { run = Cancelled }
    say texts.cancelled
  failed reason = do
    finish (RunFailed reason)
    alarm (texts.ditherFailed reason)
  skipTo event ref = do
    liftEffect (Event.preventDefault (ME.toEvent event))
    target <- H.getHTMLElementRef ref
    for_ target (liftEffect <<< HTMLElement.focus)
  -- Closed, the focus goes back to the ▾ that opened it.
  closeFormats = do
    H.modify_ _ { formatsOpen = false }
    more <- H.getHTMLElementRef formatsRef
    for_ more (liftEffect <<< HTMLElement.focus)
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

-- | The formats the download offers for the picture as it's dithered.
choicesOf :: State -> Array { format :: Format, possible :: Boolean }
choicesOf s = case s.load of
  Loaded l -> formatsFor s.settings.target { width: l.prepared.width, height: l.prepared.height }
  NoPicture -> []

-- | Downloads the result in a format: the PNG made from the result's
-- | canvas, or a machine's file as the worker made it. Nothing while
-- | there's no result.
download :: forall o m. MonadAff m => Format -> H.HalogenM State Action () o m Unit
download format = do
  s <- H.get
  case s.load, s.run of
    Loaded l, Finished r -> case format of
      Png -> do
        canvas <- H.getHTMLElementRef resultRef
        for_ canvas \element -> do
          saved <- liftAff (savePng element (downloadName s l Png))
          -- Unless another run has started meanwhile (`runs` counts on).
          H.modify_ \now -> case now.run of
            Finished done | now.runs == s.runs -> now { run = Finished done { saveFailed = not saved } }
            _ -> now
          unless saved (alarm texts.saveFailed)
      _ ->
        for_ (Array.find (\f -> f.format == extension format) r.files) \f ->
          liftEffect (saveBytes f.bytes (downloadName s l format))
    _, _ -> pure unit

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

-- | Closes the phone's settings panel, which applies its changes: a run
-- | held meanwhile starts. The focus goes back to the settings button.
-- | Unless the browser's back closed it (`fromHistory`), the step it
-- | added to the history goes too.
closePanel :: forall o m. MonadAff m => Boolean -> H.HalogenM State Action () o m Unit
closePanel fromHistory = do
  H.modify_ _ { panelOpen = false }
  unless fromHistory (liftEffect (History.back =<< Window.history =<< window))
  s <- H.get
  case s.run of
    Held _ -> restart
    _ -> pure unit
  button <- H.getHTMLElementRef settingsButtonRef
  for_ button (liftEffect <<< HTMLElement.focus)

-- | Ends the run, if any, and starts a new one for the picture and the
-- | settings, unless there's nothing to dither. A note on a file that
-- | wasn't a picture goes: this is the next action (decision 30 A). The
-- | list of formats closes, as its download waits for the new result.
-- | While the phone's panel is open, the run is held until it closes
-- | (decision 29).
restart :: forall o m. MonadAff m => H.HalogenM State Action () o m Unit
restart = do
  stopWorker
  H.modify_ _ { notAPicture = Nothing, formatsOpen = false }
  s <- H.get
  case s.load of
    Loaded l | not (isOriginal s.settings) ->
      if s.panelOpen then H.modify_ _ { run = held s.run }
      else startRun l s.settings
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
        Running r | now.runs == id -> do
          H.modify_ _ { run = Running r { progressShown = true } }
          say texts.ditheringNow
        _ -> pure unit

-- | Says a milestone of the run to screen readers, or an error, at once
-- | (decision 33). Said again, the same words are heard again.
say :: forall o m. MonadAff m => String -> H.HalogenM State Action () o m Unit
say text = H.modify_ \s -> s { status = again s.status text }

alarm :: forall o m. MonadAff m => String -> H.HalogenM State Action () o m Unit
alarm text = H.modify_ \s -> s { alert = again s.alert text }

again :: Said -> String -> Said
again said text = { text, times: said.times + 1 }

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
  let
    first = case started.load of
      NoPicture -> true
      Loaded _ -> false
  when (latest == started.loads) do
    case result of
      Left _ -> do
        H.modify_ _ { loading = Nothing, notAPicture = Just (File.name file) }
        shown <- H.gets _.load
        alarm case shown of
          Loaded _ -> texts.notAPictureKept (File.name file)
          NoPicture -> texts.notAPicture (File.name file)
      Right p -> do
        stopWorker
        s <- H.get
        prepared <- liftEffect (prepare p s.settings.target s.fit s.background)
        H.modify_ _ { load = Loaded { picture: p, prepared }, loading = Nothing, split = prepared.width / 2, splitDrag = Nothing, run = Idle }
        say (texts.loadedPicture { name: p.name, width: p.width, height: p.height })
        -- The first picture took away the button that had the focus: it
        -- goes on to the next step (`Puregrain.Web.Keys.focusAfterLoad`).
        narrow <- liftEffect narrowScreen
        for_ (focusAfterLoad { first, narrow }) \to -> do
          target <- H.getHTMLElementRef case to of
            ToTarget -> targetRef
            ToSettingsButton -> settingsButtonRef
          for_ target (liftEffect <<< HTMLElement.focus)
        -- The state change rendered the canvases; draw, and dither.
        drawOriginal prepared
        restart
