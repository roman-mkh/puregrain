-- | All the texts the web UI shows, in one place, so that a translation
-- | could replace them later (decision 12 in web/ROADMAP.md).
module Puregrain.Web.Text (texts) where

import Prelude

import Data.String.Common (joinWith)
import Puregrain.Web.Estimate (TimeLeft)
import Puregrain.Web.Prepare (Placement, isCropped, isScaledDown, leavesBackground)
import Puregrain.Web.Settings (KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Target(..), screenSizeOf)

texts
  :: { title :: String
     , choose :: String
     , loading :: String -> String
     , failed :: { name :: String, reason :: String } -> String
     , loaded :: { name :: String, width :: Int, height :: Int } -> String
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
     , dithering :: { done :: Int, total :: Int } -> String
     , timeLeft :: TimeLeft -> String
     , cancel :: String
     , cancelled :: String
     , ditherFailed :: String -> String
     , split :: String
     , save :: String
     , saveFile :: String -> String
     , saveFailed :: String
     }
texts =
  { title: "puregrain"
  , choose: "Choose a picture, or drop one onto this page."
  , loading: \name -> "Loading " <> name <> "..."
  , failed: \f -> f.name <> " couldn't be read as a picture (" <> f.reason <> ")."
  , loaded: \p -> p.name <> ": " <> show p.width <> " × " <> show p.height <> " pixels"
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
  , palette: \p -> "Palette: " <> case p of
      BlackWhite -> "black and white"
      Websafe216 -> "web-safe, 216 colors"
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
  , flatCells: "Each pixel takes the nearer of its cell's colors. Recommended: ordered dithering, 8×8."
  , gray: "Turn the picture gray first"
  , dithering: \p -> "Dithering: " <> show p.done <> " of " <> show p.total <> " rows"
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
  , save: "Download as PNG"
  , saveFile: \format -> "Download ." <> format
  , saveFailed: "The browser couldn't make the PNG."
  }
  where
  size :: forall r. { width :: Int, height :: Int | r } -> String
  size s = show s.width <> " × " <> show s.height
  machineName = case _ of
    ZxSpectrumScreen -> "ZX Spectrum"
    C64HiresScreen -> "Commodore 64"
