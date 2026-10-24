-- | The dithering settings the page offers, with their rules, as in the
-- | CLI (decisions 7 and 21 in web/ROADMAP.md): the target (any screen,
-- | or a machine's), the colors (for any screen a gray threshold, levels
-- | or a palette; for a machine, its own colors) and the method (a
-- | kernel, a Bayer map, or both). Pure, so the page and the worker share
-- | it, and specs test it.
module Puregrain.Web.Settings
  ( KernelName(..)
  , PaletteName(..)
  , MachineName(..)
  , MachinePaletteName(..)
  , Target(..)
  , Colors(..)
  , Settings
  , initial
  , allKernels
  , allPalettes
  , allMachines
  , machinePalettesOf
  , bayerSides
  , kernelId
  , paletteId
  , machineId
  , machinePaletteId
  , screenSizeOf
  , isOriginal
  , colorsAllowed
  , bayerAllowed
  , flatCells
  , chooseTarget
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

-- | The machines, as the CLI calls them, named for their screens:
-- | `ZxSpectrum` and `C64` are the palettes.
data MachineName = ZxSpectrumScreen | C64HiresScreen

derive instance Eq MachineName
derive instance Generic MachineName _
instance Show MachineName where
  show = genericShow

-- | Which of a machine's colors its cells may use, in the Spectrum's own
-- | terms, as the CLI's `--machine-palette`: all of them, the normal ones
-- | or the bright ones.
data MachinePaletteName = FullPalette | NormalPalette | BrightPalette

derive instance Eq MachinePaletteName
derive instance Generic MachinePaletteName _
instance Show MachinePaletteName where
  show = genericShow

-- | What the picture is made for: any screen, or a machine's, with that
-- | machine's colors in cells.
data Target = AnyScreen | Machine MachineName

derive instance Eq Target
derive instance Generic Target _
instance Show Target where
  show = genericShow

-- | The colors: none (the picture as it is), and then, for any screen, a
-- | gray threshold (0 to 255), levels per channel (2 to 256; gray for a
-- | gray picture) or a palette, or, for a machine, one of its palettes.
data Colors
  = Original
  | Threshold Int
  | Levels Int
  | Palette PaletteName
  | MachineColors MachinePaletteName

derive instance Eq Colors
derive instance Generic Colors _
instance Show Colors where
  show = genericShow

-- | `bayer` is the side of the Bayer map, `Nothing` for none; `gray`
-- | turns the picture gray first, like the CLI's `--gray`.
type Settings = { target :: Target, colors :: Colors, kernel :: KernelName, bayer :: Maybe Int, gray :: Boolean }

-- | Every setting at "none", for any screen: the page shows the original
-- | (decision 16).
initial :: Settings
initial = { target: AnyScreen, colors: Original, kernel: NoDiffusion, bayer: Nothing, gray: false }

allKernels :: Array KernelName
allKernels = [ NoDiffusion, FloydSteinberg, Atkinson, JarvisJudiceNinke ]

allPalettes :: Array PaletteName
allPalettes = [ BlackWhite, Websafe216, Cga16, Ansi16, Ansi256, C64, ZxSpectrum ]

allMachines :: Array MachineName
allMachines = [ ZxSpectrumScreen, C64HiresScreen ]

-- | The palettes a machine offers, the default first, as the CLI's
-- | `machinePalettesOf`.
machinePalettesOf :: MachineName -> Array MachinePaletteName
machinePalettesOf = case _ of
  ZxSpectrumScreen -> [ FullPalette, NormalPalette, BrightPalette ]
  C64HiresScreen -> [ FullPalette ]

-- | The Bayer maps offered, by side, as on the command line.
bayerSides :: Array Int
bayerSides = [ 2, 4, 8, 16 ]

-- | The CLI's names, which the messages to the worker and the downloads'
-- | names use too.
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

machineId :: MachineName -> String
machineId = case _ of
  ZxSpectrumScreen -> "zx-spectrum"
  C64HiresScreen -> "c64-hires"

machinePaletteId :: MachinePaletteName -> String
machinePaletteId = case _ of
  FullPalette -> "full"
  NormalPalette -> "normal"
  BrightPalette -> "bright"

-- | A machine's screen in pixels: the size its files hold.
screenSizeOf :: MachineName -> { width :: Int, height :: Int }
screenSizeOf = case _ of
  ZxSpectrumScreen -> { width: 256, height: 192 }
  C64HiresScreen -> { width: 320, height: 200 }

-- | Whether nothing is dithered: the colors are "none".
isOriginal :: Settings -> Boolean
isOriginal s = s.colors == Original

-- | Whether the colors go with the target: a threshold, levels or a
-- | palette with any screen, a machine's own palettes with that machine,
-- | and "none" with every target. The page offers only these.
colorsAllowed :: Target -> Colors -> Boolean
colorsAllowed target colors = case target, colors of
  _, Original -> true
  AnyScreen, MachineColors _ -> false
  AnyScreen, _ -> true
  Machine machine, MachineColors palette -> Array.elem palette (machinePalettesOf machine)
  Machine _, _ -> false

-- | Whether a Bayer map goes with these colors: over levels, as in the
-- | CLI, or inside a machine's cells; not with a threshold or a palette.
-- | With no colors yet, choosing a map also chooses them (see
-- | `chooseBayer`).
bayerAllowed :: Colors -> Boolean
bayerAllowed = case _ of
  Threshold _ -> false
  Palette _ -> false
  _ -> true

-- | Whether a machine's cells are dithered with no method at all, each
-- | pixel just the nearer of its cell's colors: valid, but rarely
-- | wanted, so the page names the recommended method then (decision 21).
flatCells :: Settings -> Boolean
flatCells s = case s.colors of
  MachineColors _ -> s.kernel == NoDiffusion && s.bayer == Nothing
  _ -> false

-- | A new target. The colors start again: none for any screen, and all of
-- | a machine's colors for a machine, so that its screen is dithered at
-- | once (decision 21). The method stays.
chooseTarget :: Target -> Settings -> Settings
chooseTarget target s =
  if target == s.target then s
  else s { target = target, colors = colors }
  where
  colors = case target of
    AnyScreen -> Original
    Machine _ -> MachineColors FullPalette

-- | New colors, if they go with the target. A Bayer map that doesn't go
-- | with them is turned off.
chooseColors :: Colors -> Settings -> Settings
chooseColors colors s =
  if colorsAllowed s.target colors then s { colors = colors, bayer = if bayerAllowed colors then s.bayer else Nothing }
  else s

-- | A new kernel. With no colors yet, they take the target's default
-- | (see `withColors`), so there's something to dither with (decision 16).
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

-- | The target's default colors where there are none yet, once a method
-- | is chosen. For any screen the CLI's: 2 levels with a Bayer map (the
-- | CLI's `--bayer` alone), else a gray threshold at 128; for a machine,
-- | all its colors. Choosing "no Bayer map" isn't a method: with no
-- | colors, it leaves them none.
withColors :: Settings -> Settings
withColors s =
  if s.colors == Original && (s.kernel /= NoDiffusion || s.bayer /= Nothing) then
    s
      { colors = case s.target of
          AnyScreen -> maybe (Threshold 128) (const (Levels 2)) s.bayer
          Machine _ -> MachineColors FullPalette
      }
  else s

-- | The settings as plain data, for a message to the worker: `target` is
-- | "any" or a machine's name; `colors` is "original", "threshold",
-- | "levels", a palette's name, or a machine palette's; `amount` the
-- | threshold or the number of levels; `bayer` a map's side or 0.
type SettingsMessage = { target :: String, colors :: String, amount :: Int, kernel :: String, bayer :: Int, gray :: Boolean }

toMessage :: Settings -> SettingsMessage
toMessage s = { target, colors, amount, kernel: kernelId s.kernel, bayer: fromMaybe 0 s.bayer, gray: s.gray }
  where
  target = case s.target of
    AnyScreen -> "any"
    Machine machine -> machineId machine
  { colors, amount } = case s.colors of
    Original -> { colors: "original", amount: 0 }
    Threshold t -> { colors: "threshold", amount: t }
    Levels n -> { colors: "levels", amount: n }
    Palette p -> { colors: paletteId p, amount: 0 }
    MachineColors p -> { colors: machinePaletteId p, amount: 0 }

-- | The settings back from a message; `Nothing` for anything the page
-- | wouldn't send.
fromMessage :: SettingsMessage -> Maybe Settings
fromMessage m = do
  target <-
    if m.target == "any" then Just AnyScreen
    else Machine <$> Array.find (\machine -> machineId machine == m.target) allMachines
  colors <- case m.colors of
    "original" -> Just Original
    "threshold" | m.amount >= 0 && m.amount <= 255 -> Just (Threshold m.amount)
    "levels" | m.amount >= 2 && m.amount <= 256 -> Just (Levels m.amount)
    name -> case target of
      AnyScreen -> Palette <$> Array.find (\p -> paletteId p == name) allPalettes
      Machine machine -> MachineColors <$> Array.find (\p -> machinePaletteId p == name) (machinePalettesOf machine)
  kernel <- Array.find (\k -> kernelId k == m.kernel) allKernels
  bayer <-
    if m.bayer == 0 then Just Nothing
    else if Array.elem m.bayer bayerSides then Just (Just m.bayer)
    else Nothing
  if not (colorsAllowed target colors) || (bayer /= Nothing && not (bayerAllowed colors)) then Nothing
  else Just { target, colors, kernel, bayer, gray: m.gray }
