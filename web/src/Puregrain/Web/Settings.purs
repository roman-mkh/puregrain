-- | The dithering settings the page offers, with their rules, as in the
-- | CLI (decision 7 in web/ROADMAP.md): the colors (a gray threshold,
-- | levels or a palette) and the method (a kernel, a Bayer map, or both).
-- | Pure, so the page and the worker share it, and specs test it.
module Puregrain.Web.Settings
  ( KernelName(..)
  , PaletteName(..)
  , Colors(..)
  , Settings
  , initial
  , allKernels
  , allPalettes
  , bayerSides
  , kernelId
  , paletteId
  , isOriginal
  , bayerAllowed
  , chooseColors
  , chooseKernel
  , chooseBayer
  , chooseGray
  , SettingsMessage
  , toMessage
  , fromMessage
  ) where

import Prelude

import Data.Array as Array
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Show.Generic (genericShow)

-- | The kernels, as the CLI calls them. A table of the web package's own:
-- | after v1, with two clients side by side, it's decided whether the
-- | library should offer one (decision 12).
data KernelName = NoDiffusion | FloydSteinberg | Atkinson | JarvisJudiceNinke

derive instance Eq KernelName
derive instance Generic KernelName _
instance Show KernelName where
  show = genericShow

-- | The palettes, as the CLI calls them.
data PaletteName = BlackWhite | Websafe216 | Cga16 | Ansi16 | Ansi256 | C64 | ZxSpectrum

derive instance Eq PaletteName
derive instance Generic PaletteName _
instance Show PaletteName where
  show = genericShow

-- | The colors: none (the picture as it is), a gray threshold (0 to 255),
-- | levels per channel (2 to 256; gray for a gray picture), or a palette.
data Colors
  = Original
  | Threshold Int
  | Levels Int
  | Palette PaletteName

derive instance Eq Colors
derive instance Generic Colors _
instance Show Colors where
  show = genericShow

-- | `bayer` is the side of the Bayer map, `Nothing` for none; `gray`
-- | turns the picture gray first, like the CLI's `--gray`.
type Settings = { colors :: Colors, kernel :: KernelName, bayer :: Maybe Int, gray :: Boolean }

-- | Every setting at "none": the page shows the original (decision 16).
initial :: Settings
initial = { colors: Original, kernel: NoDiffusion, bayer: Nothing, gray: false }

allKernels :: Array KernelName
allKernels = [ NoDiffusion, FloydSteinberg, Atkinson, JarvisJudiceNinke ]

allPalettes :: Array PaletteName
allPalettes = [ BlackWhite, Websafe216, Cga16, Ansi16, Ansi256, C64, ZxSpectrum ]

-- | The Bayer maps offered, by side, as on the command line.
bayerSides :: Array Int
bayerSides = [ 2, 4, 8, 16 ]

-- | The CLI's names, which the messages to the worker use too.
kernelId :: KernelName -> String
kernelId = case _ of
  NoDiffusion -> "none"
  FloydSteinberg -> "floyd-steinberg"
  Atkinson -> "atkinson"
  JarvisJudiceNinke -> "jjn"

paletteId :: PaletteName -> String
paletteId = case _ of
  BlackWhite -> "bw"
  Websafe216 -> "websafe216"
  Cga16 -> "cga16"
  Ansi16 -> "ansi16"
  Ansi256 -> "ansi256"
  C64 -> "c64"
  ZxSpectrum -> "zx15"

-- | Whether nothing is dithered: the colors are "none".
isOriginal :: Settings -> Boolean
isOriginal s = s.colors == Original

-- | Whether a Bayer map goes with these colors. Ordered dithering works
-- | over levels, as in the CLI, not with a threshold or a palette. With no
-- | colors yet, choosing a map also chooses 2 levels (see `chooseBayer`).
bayerAllowed :: Colors -> Boolean
bayerAllowed = case _ of
  Threshold _ -> false
  Palette _ -> false
  _ -> true

-- | New colors. A Bayer map that doesn't go with them is turned off.
chooseColors :: Colors -> Settings -> Settings
chooseColors colors s = s { colors = colors, bayer = if bayerAllowed colors then s.bayer else Nothing }

-- | A new kernel. With no colors yet, they take the CLI's default (see
-- | `withColors`), so there's something to dither with (decision 16).
chooseKernel :: KernelName -> Settings -> Settings
chooseKernel kernel s = withColors (s { kernel = kernel })

-- | A new Bayer map, or none. Ignored with colors it doesn't go with,
-- | which the page doesn't offer it with.
chooseBayer :: Maybe Int -> Settings -> Settings
chooseBayer bayer s =
  if bayer == Nothing || bayerAllowed s.colors then withColors (s { bayer = bayer })
  else s

-- | Gray first, or not. Not a method: with no colors, still nothing runs.
chooseGray :: Boolean -> Settings -> Settings
chooseGray gray s = s { gray = gray }

-- | The CLI's default colors where there are none yet, once a method is
-- | chosen: 2 levels with a Bayer map (the CLI's `--bayer` alone), else a
-- | gray threshold at 128 (its default). Choosing "no Bayer map" isn't a
-- | method: with no colors, it leaves them none.
withColors :: Settings -> Settings
withColors s =
  if s.colors == Original && (s.kernel /= NoDiffusion || s.bayer /= Nothing) then
    s { colors = maybe (Threshold 128) (const (Levels 2)) s.bayer }
  else s

-- | The settings as plain data, for a message to the worker: `colors` is
-- | "original", "threshold", "levels" or a palette's name, `amount` the
-- | threshold or the number of levels, `bayer` a map's side or 0.
type SettingsMessage = { colors :: String, amount :: Int, kernel :: String, bayer :: Int, gray :: Boolean }

toMessage :: Settings -> SettingsMessage
toMessage s = { colors, amount, kernel: kernelId s.kernel, bayer: fromMaybe 0 s.bayer, gray: s.gray }
  where
  { colors, amount } = case s.colors of
    Original -> { colors: "original", amount: 0 }
    Threshold t -> { colors: "threshold", amount: t }
    Levels n -> { colors: "levels", amount: n }
    Palette p -> { colors: paletteId p, amount: 0 }

-- | The settings back from a message; `Nothing` for anything the page
-- | wouldn't send.
fromMessage :: SettingsMessage -> Maybe Settings
fromMessage m = do
  colors <- case m.colors of
    "original" -> Just Original
    "threshold" | m.amount >= 0 && m.amount <= 255 -> Just (Threshold m.amount)
    "levels" | m.amount >= 2 && m.amount <= 256 -> Just (Levels m.amount)
    name -> Palette <$> Array.find (\p -> paletteId p == name) allPalettes
  kernel <- Array.find (\k -> kernelId k == m.kernel) allKernels
  bayer <-
    if m.bayer == 0 then Just Nothing
    else if Array.elem m.bayer bayerSides then Just (Just m.bayer)
    else Nothing
  if bayer /= Nothing && not (bayerAllowed colors) then Nothing
  else Just { colors, kernel, bayer, gray: m.gray }
