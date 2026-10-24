-- | Saving the result: the files' names, made from the picture's name and
-- | the settings, the name on a ZX Spectrum tape, and the downloads
-- | themselves (FFI in `Save.js`).
module Puregrain.Web.Save (fileName, tapeName, savePng, saveBytes) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.Array as Array
import Data.ArrayBuffer.Types (Uint8Array)
import Data.Char (toCharCode)
import Data.Maybe (Maybe(..), maybe)
import Data.String.CodeUnits as CodeUnits
import Data.String.Common (joinWith)
import Data.String.Pattern (Pattern(..))
import Effect (Effect)
import Effect.Aff (Aff)
import Puregrain.Web.Settings (Colors(..), KernelName(..), MachinePaletteName(..), Settings, Target(..), kernelId, machineId, machinePaletteId, paletteId)
import Web.HTML.HTMLElement (HTMLElement)

-- | A file's name for the result: the picture's name without its
-- | extension (what follows its last dot, unless the dot starts the
-- | name), then the settings in the form's order, with the CLI's names,
-- | and the format's extension. A machine's palette appears unless it's
-- | the full one; a setting at none is left out; colors at none, with
-- | nothing to save, give `original`.
-- |
-- | ```purescript
-- | fileName "photo.jpg" (initial { colors = Levels 4, kernel = Atkinson, bayer = Just 8 }) "png"
-- |   == "photo-levels4-atkinson-bayer8.png"
-- | ```
fileName :: String -> Settings -> String -> String
fileName name s extension = joinWith "-" ([ stem name ] <> target <> colors <> kernel <> bayer <> gray) <> "." <> extension
  where
  target = case s.target of
    AnyScreen -> []
    Machine machine -> [ machineId machine ]
  colors = case s.colors of
    Original -> [ "original" ]
    Threshold t -> [ "threshold" <> show t ]
    Levels n -> [ "levels" <> show n ]
    Palette p -> [ paletteId p ]
    MachineColors FullPalette -> []
    MachineColors p -> [ machinePaletteId p ]
  kernel = if s.kernel == NoDiffusion then [] else [ kernelId s.kernel ]
  bayer = maybe [] (\side -> [ "bayer" <> show side ]) s.bayer
  gray = if s.gray then [ "gray" ] else []

-- | The name on a ZX Spectrum tape, by the CLI's rule, from the picture's
-- | name: without its extension, printable ASCII only (codes 32 to 126),
-- | the first 10 characters. `puregrain` when nothing printable is left
-- | (decision 21).
tapeName :: String -> String
tapeName name = if CodeUnits.length kept == 0 then "puregrain" else kept
  where
  kept = CodeUnits.take 10 (CodeUnits.fromCharArray (Array.filter printable (CodeUnits.toCharArray (stem name))))
  printable c = toCharCode c >= 32 && toCharCode c <= 126

-- | The name without its extension: what precedes its last dot, unless
-- | that dot starts the name, as the CLI's `splitFileName`.
stem :: String -> String
stem name = case CodeUnits.lastIndexOf (Pattern ".") name of
  Just i | i > 0 -> CodeUnits.take i name
  _ -> name

foreign import savePngImpl :: HTMLElement -> String -> Effect (Promise Boolean)

-- | Saves a canvas's pixels as a PNG file with this name: the browser's
-- | download. False when the browser couldn't make the PNG.
savePng :: HTMLElement -> String -> Aff Boolean
savePng canvas name = toAffE (savePngImpl canvas name)

-- | Saves bytes as a file with this name, a machine's file: the browser's
-- | download.
foreign import saveBytes :: Uint8Array -> String -> Effect Unit
