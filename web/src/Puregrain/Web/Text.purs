-- | All the texts the web UI shows, in one place, so that a translation
-- | could replace them later (decision 12 in web/ROADMAP.md).
module Puregrain.Web.Text (texts) where

import Prelude

import Data.Maybe (Maybe(..), maybe)
import Data.String.Common (joinWith)
import Puregrain.Web.Download (Format(..))
import Puregrain.Web.Estimate (TimeLeft)
import Puregrain.Web.Prepare (Placement, isCropped, isScaledDown, leavesBackground)
import Puregrain.Web.Settings (Colors(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Settings, Target(..), screenSizeOf)

texts
  :: { title :: String
     , labName :: String
     , tagline :: String
     , taglineShort :: String
     , help :: String
     , source :: String
     , darkTheme :: String
     , linksLabel :: String
     , settingsLabel :: String
     , pictureLabel :: String
     , skipToSettings :: String
     , skipToPicture :: String
     , originalNamed :: String -> String
     , resultNamed :: Settings -> String
     , describe :: Settings -> String
     , versions :: String -> String
     , codeLicense :: String
     , logoLicense :: String
     , onGitHub :: String
     , picture :: String
     , chooseFirst :: String
     , chooseAnother :: String
     , dropHint :: String
     , pictureSize :: { width :: Int, height :: Int } -> String
     , targetLine :: Target -> String
     , palettesGroup :: String
     , fewerLevels :: String
     , moreLevels :: String
     , method :: String
     , useBayer2 :: String
     , hideSettings :: String
     , showSettings :: String
     , apply :: String
     , dropTitle :: String
     , dropOr :: String
     , formats :: String
     , description :: String
     , promises :: String
     , loading :: String -> String
     , notAPicture :: String -> String
     , notAPictureKept :: String -> String
     , dropToLoad :: String
     , original :: String
     , result :: String
     , showWholeOriginal :: String
     , showWholeResult :: String
     , zoom :: String
     , zoomLevel :: Int -> String
     , target :: String
     , targetName :: Target -> String
     , colors :: String
     , colorsOriginal :: String
     , colorsThreshold :: String
     , colorsLevels :: String
     , palette :: PaletteName -> String
     , machinePalette :: MachineName -> MachinePaletteName -> String
     , sizeNote :: MachineName -> { width :: Int, height :: Int } -> String
     , fitChoice :: String
     , fitted :: MachineName -> { picture :: { width :: Int, height :: Int }, placement :: Placement } -> String
     , background :: String
     , transparentParts :: String
     , thresholdValue :: String
     , levelsValue :: String
     , kernel :: String
     , kernelName :: KernelName -> String
     , bayer :: String
     , bayerOff :: String
     , bayerSide :: Int -> String
     , bayerNeedsLevels :: String
     , flatCells :: String
     , gray :: String
     , originalShown :: String
     , originalShownPhone :: String
     , loadedPicture :: { name :: String, width :: Int, height :: Int } -> String
     , ditheringNow :: String
     , done :: Settings -> String
     , dithering :: { done :: Int, total :: Int, left :: Maybe TimeLeft } -> String
     , ditheringLabel :: String
     , timeLeft :: TimeLeft -> String
     , cancel :: String
     , cancelled :: String
     , ditherFailed :: String -> String
     , split :: String
     , splitValue :: Int -> Int -> String
     , downloadAs :: Format -> String
     , formatName :: Format -> String
     , needsScreen :: { width :: Int, height :: Int } -> String
     , moreFormats :: String
     , saveFailed :: String
     , withKeys :: String -> String -> String
     , chooseKeys :: String
     , downloadKeys :: String
     , cancelKeys :: String
     }
texts =
  { title: "puregrain"
  -- The header and the footer (decisions 29 and 32): the page is
  -- "puregrain lab", the library "puregrain".
  , labName: "lab"
  , tagline: "The puregrain library, at work in your browser: your pictures are never uploaded."
  , taglineShort: "Runs in your browser: nothing is uploaded."
  , help: "Help"
  , source: "Source"
  , darkTheme: "Dark theme"
  , linksLabel: "Links"
  , settingsLabel: "Settings"
  , pictureLabel: "The picture"
  -- Shown on the first Tab (decision 33).
  , skipToSettings: "Skip to the settings"
  , skipToPicture: "Skip to the picture"
  -- The pictures' names for screen readers, and the result's description
  -- in the menus' words: "4 levels, Atkinson".
  , originalNamed: \name -> "The original: " <> name
  , resultNamed: \settings -> "The result: " <> texts.describe settings
  , describe: \settings ->
      joinWith ", "
        ( ( case settings.target of
              AnyScreen -> []
              Machine machine -> [ machineName machine ]
          )
            <>
              ( case settings.colors of
                  Original -> []
                  Threshold t -> [ "threshold " <> show t ]
                  Levels n -> [ show n <> " levels" ]
                  Palette p -> [ texts.palette p ]
                  MachineColors p -> case settings.target of
                    Machine machine -> [ texts.machinePalette machine p ]
                    AnyScreen -> []
              )
            <> (if settings.kernel == NoDiffusion then [] else [ texts.kernelName settings.kernel ])
            <> maybe [] (\side -> [ "ordered dithering " <> texts.bayerSide side ]) settings.bayer
            <> (if settings.gray then [ "gray first" ] else [])
        )
  , versions: \library -> "puregrain lab v2" <> (if library == "" then "" else ", built on puregrain " <> library)
  , codeLicense: "The code: MIT"
  , logoLicense: "The logo: its own terms"
  , onGitHub: "puregrain on GitHub"
  , picture: "Picture"
  -- The settings' column (decision 31): its numbered steps.
  , chooseFirst: "Choose a picture…"
  , chooseAnother: "Choose another…"
  , dropHint: "Or drop one anywhere on this page."
  , pictureSize: \p -> show p.width <> " × " <> show p.height <> " pixels"
  , targetLine: case _ of
      AnyScreen -> "any size, the colors you choose"
      Machine m ->
        let
          s = screenSizeOf m
        in
          show s.width <> " × " <> show s.height <> ", 2 colors per 8×8 cell"
  , palettesGroup: "Palettes"
  , fewerLevels: "Fewer levels"
  , moreLevels: "More levels"
  , method: "Method"
  , useBayer2: "Use 2×2"
  , hideSettings: "Hide the settings"
  , showSettings: "Show the settings"
  -- The phone's settings panel closes with it, and dithers then.
  , apply: "Apply"
  -- The empty picture area (decisions 29 and 30): the drop zone, how to
  -- start, and the promises.
  , dropTitle: "Drop a picture here"
  , dropOr: "or"
  , formats: "PNG, JPEG, GIF, WebP or BMP."
  , description: "Choose a target, colors and a method in the settings: the result shows beside the original, to compare, and saves as a PNG, or as a ZX Spectrum's or a C64's own files."
  , promises: "Everything runs in your browser: your pictures are never uploaded. No ads, no registration, no tracking, and it's free."
  , loading: \name -> "Loading " <> name <> "…"
  , notAPicture: \name -> name <> " isn't a picture."
  , notAPictureKept: \name -> name <> " isn't a picture; the current one stays."
  , dropToLoad: "Drop to load the picture"
  -- Above the picture's corners, either side of the split.
  , original: "Original"
  , result: "Result"
  , showWholeOriginal: "Show the whole original"
  , showWholeResult: "Show the whole result"
  , zoom: "Zoom"
  , zoomLevel: \zoom -> show zoom <> "×"
  , target: "Target"
  , targetName: case _ of
      AnyScreen -> "Any screen"
      Machine machine -> machineName machine
  , colors: "Colors"
  , colorsOriginal: "None: the original"
  , colorsThreshold: "Gray, black and white at a threshold"
  , colorsLevels: "Levels per channel"
  -- Shown in the colors' menu under "Palettes".
  , palette: case _ of
      BlackWhite -> "Black and white"
      Websafe216 -> "Web-safe, 216 colors"
      Cga16 -> "CGA, EGA, VGA, 16 colors"
      Ansi16 -> "ANSI terminal, 16 colors"
      Ansi256 -> "xterm, 256 colors"
      C64 -> "Commodore 64, 16 colors"
      ZxSpectrum -> "ZX Spectrum, 15 colors"
  , machinePalette: \machine palette -> case machine, palette of
      C64HiresScreen, _ -> "16 colors"
      ZxSpectrumScreen, FullPalette -> "15 colors, normal and bright"
      ZxSpectrumScreen, NormalPalette -> "8 colors, normal only"
      ZxSpectrumScreen, BrightPalette -> "8 colors, bright only"
  , sizeNote: \machine picture ->
      let
        screen = screenSizeOf machine
      in
        "A " <> machineName machine <> " screen is " <> show screen.width <> " × " <> show screen.height
          <> "; this picture is " <> show picture.width <> " × " <> show picture.height
          <> ". Any size works for a PNG; the machine's own files need the screen's size."
  , fitChoice: "Fit the picture to the screen"
  , fitted: \machine f ->
      let
        screen = screenSizeOf machine
        done =
          (if isScaledDown f.picture f.placement then [ "scaled down from " <> size f.picture <> " to " <> size f.placement ] else [ "not scaled" ])
            <> (if isCropped screen f.placement then [ "cropped to the screen" ] else [])
            <> (if leavesBackground screen f.placement then [ "the background around it" ] else [])
      in
        "Fitted to the " <> machineName machine <> "'s screen, " <> size screen <> ": " <> joinWith ", " done <> "."
  , background: "Background"
  , transparentParts: "The picture's transparent parts are put onto the background color."
  , thresholdValue: "Threshold (0-255)"
  , levelsValue: "Levels (2-256)"
  , kernel: "Error diffusion"
  , kernelName: case _ of
      NoDiffusion -> "None"
      FloydSteinberg -> "Floyd-Steinberg"
      Atkinson -> "Atkinson"
      JarvisJudiceNinke -> "Jarvis-Judice-Ninke"
  , bayer: "Ordered dithering (Bayer map)"
  , bayerOff: "None"
  , bayerSide: \side -> show side <> "×" <> show side
  , bayerNeedsLevels: "Ordered dithering works over levels, not with a threshold or a palette. For black and white, choose 2 levels and \"Turn the picture gray first\"."
  , flatCells: "Each pixel takes the nearer of its cell's colors. Recommended: ordered dithering, 2×2, the look of the time; 4×4 for smoother tones."
  , gray: "Turn the picture gray first"
  , originalShown: "The original is shown. Choose colors or a method to dither it."
  -- On a phone the settings are behind the header's button.
  , originalShownPhone: "The original is shown. Open the settings to dither it."
  -- What screen readers hear of a picture loaded, and of a run: its
  -- start, once its progress shows, and its end (decision 33).
  , loadedPicture: \p -> "Loaded: " <> p.name <> ", " <> show p.width <> " × " <> show p.height <> " pixels."
  , ditheringNow: "Dithering…"
  , done: \settings -> "Done: " <> texts.describe settings <> "."
  -- The time left first, what matters most, and the rows after it, where
  -- their frequent changes push nothing.
  , dithering: \p ->
      let
        rows = show p.done <> "/" <> show p.total <> " rows"
      in
        "Dithering: " <> case p.left of
          Just t -> texts.timeLeft t <> " (" <> rows <> ")"
          Nothing -> rows
  , ditheringLabel: "Dithering"
  , timeLeft: \t ->
      if t.minutes == 0 && t.seconds == 0 then "a few seconds left"
      else
        "about "
          <> (if t.minutes > 0 then show t.minutes <> " min" else "")
          <> (if t.minutes > 0 && t.seconds > 0 then " " else "")
          <> (if t.seconds > 0 then show t.seconds <> " s" else "")
          <> " left"
  , cancel: "Cancel"
  , cancelled: "Cancelled; the original is shown."
  , ditherFailed: \reason -> "The dithering failed: " <> reason
  , split: "Split: the original on the left, the result on the right"
  , splitValue: \split width -> "column " <> show split <> " of " <> show width
  -- The download (decision 31): the button names its format, the list
  -- of formats says what each file is.
  , downloadAs: \format -> "Download " <> case format of
      Png -> "PNG"
      Scr -> "SCR"
      Tap -> "TAP"
      Prg -> "PRG"
      Art -> "ART"
  , formatName: case _ of
      Png -> "Picture"
      Scr -> "ZX Spectrum screen"
      Tap -> "ZX Spectrum tape, loads by itself"
      Prg -> "C64 program with a viewer"
      Art -> "Art Studio picture"
  , needsScreen: \screen -> "needs a " <> size screen <> " picture"
  , moreFormats: "More formats"
  , saveFailed: "The browser couldn't make the PNG."
  -- The shortcuts in the tooltips (decision 33), written the same way on
  -- every system: Ctrl works on a Mac too, as does Cmd.
  , withKeys: \label keys -> label <> " (" <> keys <> ")"
  , chooseKeys: "Ctrl+O"
  , downloadKeys: "Ctrl+S"
  , cancelKeys: "Esc"
  }
  where
  size :: forall r. { width :: Int, height :: Int | r } -> String
  size s = show s.width <> " × " <> show s.height
  machineName = case _ of
    ZxSpectrumScreen -> "ZX Spectrum"
    C64HiresScreen -> "Commodore 64"
