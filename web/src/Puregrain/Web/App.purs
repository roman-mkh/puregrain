-- | The web UI's component (web/ROADMAP.md): choose a picture or drop
-- | one, choose the settings, for any screen or a machine's, see the
-- | result, dithered in a worker with progress and cancelling, over the
-- | original at whole-number zoom, split by a slider, and save it as a
-- | PNG, or as the machine's own files.
module Puregrain.Web.App (component) where

import Prelude

import Control.Monad.Except (runExcept)
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.Int as Int
import Data.Maybe (Maybe(..), isJust)
import Effect (Effect)
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
import Puregrain.Web.Message (FileBytes, Reply(..), describe, jobMessage, readReply)
import Puregrain.Web.Picture (Picture)
import Puregrain.Web.Picture as Picture
import Puregrain.Web.Pixels (copyPixels, toImageData, transferable)
import Puregrain.Web.Prepare (Background, Placement, backgroundFromHex, backgroundHex, backgroundShows, fitOnto, flatten, placementOn, screenToFit, white)
import Puregrain.Web.Save (fileName, saveBytes, savePng, tapeName)
import Puregrain.Web.Screen (pixelRatio)
import Puregrain.Web.Settings (Colors(..), Settings, Target(..), allKernels, allMachines, allPalettes, bayerAllowed, bayerSides, chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, flatCells, initial, isOriginal, kernelId, machineId, machinePaletteId, machinePalettesOf, paletteId, screenSizeOf)
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

-- | The dithering: none, running (rows done of all), finished with the
-- | result, a machine's files, and whether saving the PNG failed;
-- | cancelled, or failed.
data Run
  = Idle
  | Running { done :: Int, total :: Int }
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
  }

data Action
  = Initialize
  | Resized
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

originalRef :: H.RefLabel
originalRef = H.RefLabel "original"

resultRef :: H.RefLabel
resultRef = H.RefLabel "result"

component :: forall q i o m. MonadAff m => H.Component q i o m
component = H.mkComponent
  { initialState: const
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
  Loaded { picture: p, prepared } ->
    let
      size = cssSize state.pixelRatio state.zoom { width: prepared.width, height: prepared.height }
      sizeStyle = "width: " <> show size.width <> "px; height: " <> show size.height <> "px"
      -- The result's left edge is cut at the split, so the original shows
      -- on its left: at whole picture columns, so at whole screen pixels.
      cut = "clip-path: inset(0 0 0 " <> show (toNumber state.split * 100.0 / toNumber prepared.width) <> "%)"
      finished = isFinished state.run
    in
      -- The parts whose elements come and go sit in fixed containers, so
      -- the canvases keep their places among their siblings: Halogen
      -- matches unkeyed children by position, and would otherwise rebuild
      -- a canvas, blank, whenever the progress bar appears or goes.
      [ HH.p_ [ HH.text (texts.loaded { name: p.name, width: p.width, height: p.height }) ]
      , HH.div [ HP.class_ (H.ClassName "settings") ]
          ( settingsForm state.settings
              { size: { width: p.width, height: p.height }, transparent: p.transparent, fit: state.fit, fitted: prepared.fitted, background: state.background }
          )
      , HH.div [ HP.class_ (H.ClassName "status") ] (runStatus state.run)
      , HH.label_
          [ HH.text texts.zoom
          , HH.select [ HE.onValueChange ZoomChosen ]
              (map (\z -> option (show z) (texts.zoomLevel z) (z == state.zoom)) zooms)
          ]
      , HH.label_
          [ HH.text texts.split
          , HH.input
              [ HP.type_ HP.InputRange
              , HP.min 0.0
              , HP.max (toNumber prepared.width)
              , HP.value (show state.split)
              , HP.disabled (not finished)
              , HE.onValueInput SplitMoved
              ]
          ]
      -- The original and the result stacked in one box (decision 15), so
      -- they share its zoom and scrolling; the result only once there is
      -- one.
      , HH.div [ HP.class_ (H.ClassName "view") ]
          [ HH.div [ HP.class_ (H.ClassName "layers") ]
              [ HH.canvas
                  [ HP.ref originalRef
                  , HP.class_ (H.ClassName "picture")
                  , HP.width prepared.width
                  , HP.height prepared.height
                  , HP.style sizeStyle
                  ]
              , HH.canvas
                  [ HP.ref resultRef
                  , HP.classes [ H.ClassName "picture", H.ClassName "result" ]
                  , HP.width prepared.width
                  , HP.height prepared.height
                  , HP.style (sizeStyle <> "; " <> cut)
                  , HP.prop (H.PropName "hidden") (not finished)
                  ]
              ]
          ]
      ]

-- | The picture's side of the form: its size and transparency, the fit
-- | asked for and where it went, and the background color.
type PictureForm =
  { size :: { width :: Int, height :: Int }
  , transparent :: Boolean
  , fit :: Boolean
  , fitted :: Maybe { screen :: { width :: Int, height :: Int }, placement :: Placement }
  , background :: Background
  }

settingsForm :: forall m. Settings -> PictureForm -> Array (H.ComponentHTML Action () m)
settingsForm s pic =
  [ HH.label_
      [ HH.text texts.target
      , HH.select [ HE.onValueChange TargetChosen ]
          ( [ option "any" (texts.targetName AnyScreen) (s.target == AnyScreen) ]
              <> map (\m -> option (machineId m) (texts.targetName (Machine m)) (s.target == Machine m)) allMachines
          )
      ]
  ]
    <> fitting s.target
    <> background
    <>
      [ HH.label_
          [ HH.text texts.colors
          , HH.select [ HE.onValueChange ColorsChosen ]
              ([ option "original" texts.colorsOriginal (s.colors == Original) ] <> colorsOf s.target)
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
    <> (if flatCells s then [ HH.small_ [ HH.text texts.flatCells ] ] else [])
    <>
      [ HH.label_
          [ HH.input [ HP.type_ HP.InputCheckbox, HP.checked s.gray, HE.onChecked GrayChosen ]
          , HH.text texts.gray
          ]
      ]
  where
  -- For a machine and a picture of another size: what happens to it, and
  -- the choice to fit it to the screen (decision 22).
  fitting = case _ of
    Machine m | screenSizeOf m /= pic.size ->
      [ HH.p_
          [ HH.small_
              [ HH.text case pic.fitted of
                  Just f -> texts.fitted m { picture: pic.size, placement: f.placement }
                  Nothing -> texts.sizeNote m pic.size
              ]
          ]
      , HH.label_
          [ HH.input [ HP.type_ HP.InputCheckbox, HP.checked pic.fit, HE.onChecked FitChosen ]
          , HH.text texts.fitChoice
          ]
      ]
    _ -> []
  -- Whenever the background shows in the result (decision 27).
  background =
    if backgroundShows pic.transparent pic.fitted then
      [ HH.label_
          [ HH.text texts.background
          , HH.input [ HP.type_ HP.InputColor, HP.value ("#" <> backgroundHex pic.background), HE.onValueChange BackgroundChosen ]
          ]
      ]
        <> (if pic.transparent then [ HH.small_ [ HH.text texts.transparentParts ] ] else [])
    else []
  colorsOf = case _ of
    AnyScreen ->
      [ option "threshold" texts.colorsThreshold (isThreshold s.colors)
      , option "levels" texts.colorsLevels (isLevels s.colors)
      ]
        <> map (\p -> option (paletteId p) (texts.palette p) (s.colors == Palette p)) allPalettes
    Machine m -> map (\p -> option (machinePaletteId p) (texts.machinePalette m p) (s.colors == MachineColors p)) (machinePalettesOf m)
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
  Finished r ->
    [ HH.button [ HE.onClick (const Save) ] [ HH.text texts.save ] ]
      <> map (\f -> HH.button [ HE.onClick (const (SaveFile f.format)) ] [ HH.text (texts.saveFile f.format) ]) r.files
      <> (if r.saveFailed then [ HH.p_ [ HH.text texts.saveFailed ] ] else [])
  Cancelled -> [ HH.p_ [ HH.text texts.cancelled ] ]
  RunFailed reason -> [ HH.p_ [ HH.text (texts.ditherFailed reason) ] ]

option :: forall m. String -> String -> Boolean -> H.ComponentHTML Action () m
option value label selected = HH.option [ HP.value value, HP.selected selected ] [ HH.text label ]

isFinished :: Run -> Boolean
isFinished = case _ of
  Finished _ -> true
  _ -> false

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
        Right (Progress p) -> H.modify_ _ { run = Running p }
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
    liftEffect (Worker.postMessage' (jobMessage job) [ transferable copy ] worker)
    H.modify_ _ { worker = Just worker, run = Running { done: 0, total: prepared.height } }

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
