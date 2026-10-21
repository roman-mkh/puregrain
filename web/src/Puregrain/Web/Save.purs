-- | Saving the result as a PNG file: its name, made from the picture's
-- | name and the settings, and the download itself (FFI in `Save.js`).
module Puregrain.Web.Save (fileName, savePng) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.Maybe (Maybe(..), maybe)
import Data.String.CodeUnits as CodeUnits
import Data.String.Common (joinWith)
import Data.String.Pattern (Pattern(..))
import Effect (Effect)
import Effect.Aff (Aff)
import Puregrain.Web.Settings (Colors(..), KernelName(..), Settings, kernelId, paletteId)
import Web.HTML.HTMLElement (HTMLElement)

-- | The result's file name: the picture's name without its extension
-- | (what follows its last dot, unless the dot starts the name), then the
-- | settings in the form's order, with the CLI's names, and `.png`. A
-- | setting at none is left out; colors at none, with nothing to save,
-- | give `original`.
-- |
-- | ```purescript
-- | fileName "photo.jpg" (initial { colors = Levels 4, kernel = Atkinson, bayer = Just 8 })
-- |   == "photo-levels4-atkinson-bayer8.png"
-- | ```
fileName :: String -> Settings -> String
fileName name s = joinWith "-" ([ stem ] <> colors <> kernel <> bayer <> gray) <> ".png"
  where
  stem = case CodeUnits.lastIndexOf (Pattern ".") name of
    Just i | i > 0 -> CodeUnits.take i name
    _ -> name
  colors = case s.colors of
    Original -> [ "original" ]
    Threshold t -> [ "threshold" <> show t ]
    Levels n -> [ "levels" <> show n ]
    Palette p -> [ paletteId p ]
  kernel = if s.kernel == NoDiffusion then [] else [ kernelId s.kernel ]
  bayer = maybe [] (\side -> [ "bayer" <> show side ]) s.bayer
  gray = if s.gray then [ "gray" ] else []

foreign import savePngImpl :: HTMLElement -> String -> Effect (Promise Boolean)

-- | Saves a canvas's pixels as a PNG file with this name: the browser's
-- | download. False when the browser couldn't make the PNG.
savePng :: HTMLElement -> String -> Aff Boolean
savePng canvas name = toAffE (savePngImpl canvas name)
