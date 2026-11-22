-- | The CLI's decisions, as pure functions: which kind of dithering a
-- | command line asks for, and how a color pixel becomes gray. Kept out of
-- | `Puregrain.Cli.Main` (which only does I/O) so they can be tested.
module Puregrain.Cli.Pipeline
  ( Pipeline(..)
  , pipelineFor
  , DitheredScreen(..)
  , ditherScreen
  , screenImage
  , screenFile
  , tapeFile
  , programFile
  , artStudioFile
  , tapeName
  , screenSizeCheck
  , paramsOf
  , kernelOf
  , paletteOf
  , gammaOf
  , isNeutral
  , toNeutral
  ) where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array as Array
import Data.Char (toCharCode)
import Data.Either (Either(..))
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..), maybe)
import Data.Show.Generic (genericShow)
import Data.String.CodeUnits as CodeUnits
import Puregrain (DitherParams, Gamma, Kernel, Quantize, RGB(..), ThresholdMap, ansi16, ansi256, atkinson, bayer, blackWhite, burkes, c64, cga16, defaults, evenRamp, fan, floydSteinberg, gamma1p2, gamma1p5, gamma1p8, gammaOff, gammaSrgb, jarvisJudiceNinke, nearestColor, noDiffusion, nearestLevel, ordered, perChannel, shiauFan, shiauFan2, sierra2, sierra3, sierraLite, stucki, raster, serpentine, threshold, toGray, websafe216, withGamma, withKernel, withScan, zxSpectrum)
import Partial.Unsafe (unsafeCrashWith)
-- The cells and the machines aren't in the facade (a specialty, "start
-- closed"), so the CLI imports them directly, as any application would.
import Puregrain.Cells (CellQuantizer, ditherCellsBy, nearestInCell, orderedInCell)
import Puregrain.Cli.Options (FormatName(..), GammaName(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), QuantizerChoice(..), formatName, splitFileName)
import Puregrain.Machine.C64 as C64
import Puregrain.Machine.ZxSpectrum as Zx

-- | Dither in one gray channel, in RGB, or to a machine's screen (RGB,
-- | cell by cell, with the machine's palette and a rule inside the cells).
data Pipeline
  = Gray (Quantize Number)
  | Color (Quantize RGB)
  | Screen { machine :: MachineName, palette :: MachinePaletteName, rule :: CellQuantizer }

-- | A threshold always runs on gray. Levels, with or without `--bayer`,
-- | run on gray when the image is gray, and per channel (scalarED)
-- | otherwise. A palette always runs on RGB (vectorED) — its colors
-- | needn't be gray, even for a gray input; so does a machine's screen,
-- | with the nearer of each cell's colors, or with `--bayer` ordered
-- | dithering inside the cells.
-- | `grayImage` is true for an all-neutral input, or after `--gray`. This
-- | is the table in cli/README.md, "How the output is chosen".
pipelineFor :: QuantizerChoice -> Boolean -> Pipeline
pipelineFor choice grayImage = case choice of
  Threshold t -> Gray (threshold t)
  Levels n
    | grayImage -> Gray (nearestLevel (evenRamp n))
    | otherwise -> Color (perChannel (nearestLevel (evenRamp n)))
  Palette p -> Color (nearestColor (paletteOf p))
  Bayer { side, levels }
    | grayImage -> Gray (ordered (bayerOf side) (evenRamp levels))
    | otherwise -> Color (perChannel (ordered (bayerOf side) (evenRamp levels)))
  Machine { name, palette, bayer: side } ->
    Screen { machine: name, palette, rule: maybe nearestInCell (orderedInCell <<< bayerOf) side }

-- | A machine's screen after dithering: the picture, and each cell's
-- | choice in the machine's own terms, which its files need.
data DitheredScreen
  = ZxDithered { cells :: Array (Array Zx.Attribute), image :: Array (Array RGB) }
  | C64HiresDithered { cells :: Array (Array C64.HiresCell), image :: Array (Array RGB) }

derive instance Eq DitheredScreen
derive instance Generic DitheredScreen _
instance Show DitheredScreen where
  show = genericShow

-- | The dithered picture.
screenImage :: DitheredScreen -> Array (Array RGB)
screenImage = case _ of
  ZxDithered s -> s.image
  C64HiresDithered s -> s.image

-- | Dithers an RGB image to the machine's screen, cell by cell, with the
-- | settings (kernel, gamma), the machine's palette and the rule inside the
-- | cells.
-- | (A machine's palette names are checked against what it offers before:
-- | `c64-hires` has only the full one.)
ditherScreen :: DitherParams -> MachineName -> MachinePaletteName -> CellQuantizer -> Array (Array RGB) -> DitheredScreen
ditherScreen params machine palette rule image = case machine of
  ZxSpectrumScreen -> ZxDithered (ditherCellsBy params rule zxMode image)
  C64HiresScreen -> C64HiresDithered (ditherCellsBy params rule C64.hiresScreen image)
  where
  zxMode = case palette of
    FullPalette -> Zx.screen
    NormalPalette -> Zx.normalScreen
    BrightPalette -> Zx.brightScreen

-- | The ZX Spectrum's screen file for a dithered screen, as bytes: a .scr
-- | file. `Left` for a screen of the wrong size, which `screenSizeCheck`
-- | rules out before dithering, and for another machine's screen, which
-- | the options rule out.
screenFile :: DitheredScreen -> Either String (Array Int)
screenFile = case _ of
  ZxDithered s -> Zx.toScr s
  C64HiresDithered _ -> Left "a .scr file holds a ZX Spectrum screen, not a C64's"

-- | The ZX Spectrum's screen as a tape image that loads and shows it, as
-- | bytes: a .tap file, with the name on the tape. `Left` as for
-- | `screenFile`.
tapeFile :: String -> DitheredScreen -> Either String (Array Int)
tapeFile name = case _ of
  ZxDithered s -> Zx.toTap name s
  C64HiresDithered _ -> Left "a .tap file holds a ZX Spectrum screen, not a C64's"

-- | The C64 program that shows a dithered hires screen, as bytes: a .prg
-- | file. `Left` as for `screenFile`, and for another machine's screen.
programFile :: DitheredScreen -> Either String (Array Int)
programFile = case _ of
  C64HiresDithered s -> C64.toHiresPrg s
  ZxDithered _ -> Left "a .prg file holds a C64 hires screen, not a ZX Spectrum's"

-- | An Art Studio picture file of a dithered hires screen, as bytes: an
-- | .art file. `Left` as for `programFile`.
artStudioFile :: DitheredScreen -> Either String (Array Int)
artStudioFile = case _ of
  C64HiresDithered s -> C64.toArtStudio s
  ZxDithered _ -> Left "an .art file holds a C64 hires screen, not a ZX Spectrum's"

-- | The name on the tape, from the output path: the file's name without
-- | its directory and extension, printable ASCII characters only, the
-- | first 10 (a Spectrum tape name's length).
tapeName :: String -> String
tapeName path = CodeUnits.take 10 (CodeUnits.fromCharArray (Array.filter printable (CodeUnits.toCharArray (splitFileName path).stem)))
  where
  printable c = toCharCode c >= 32 && toCharCode c <= 126

-- | What to say about an image that isn't the size of the machine's
-- | screen, before dithering it. A PNG can have any size (a poster in the
-- | machine's style, say), so for one it's only a note: `Right (Just
-- | note)`. The machine's screen file holds exactly one screen, so for
-- | that it's an error, `Left`, before any time goes into dithering.
-- | `Right Nothing` for an image of the screen's size.
screenSizeCheck :: FormatName -> MachineName -> Int -> Int -> Either String (Maybe String)
screenSizeCheck format machine width height =
  if width == screen.width && height == screen.height then Right Nothing
  else case format of
    Png -> Right (Just ("Note: " <> screen.name <> " is " <> screenSize <> ", this image is " <> size <> " (any size works for a PNG)"))
    Scr -> Left (machineFileOnly Scr)
    Tap -> Left (machineFileOnly Tap)
    Prg -> Left (machineFileOnly Prg)
    Art -> Left (machineFileOnly Art)
  where
  screen = case machine of
    ZxSpectrumScreen -> { width: 256, height: 192, name: "a ZX Spectrum screen" }
    C64HiresScreen -> { width: 320, height: 200, name: "a C64 hires screen" }
  screenSize = show screen.width <> "x" <> show screen.height
  size = show width <> "x" <> show height
  machineFileOnly f =
    "--format " <> formatName f <> " needs a " <> screenSize <> " image, " <> screen.name <> "; this one is " <> size
      <> ". Resize it first (see \"Machine screens\" in cli/README.md), or write a PNG, which can have any size."

-- | The `--bayer` option only accepts powers of 2, for which `bayer`
-- | always has a map.
bayerOf :: Int -> ThresholdMap
bayerOf side = case bayer side of
  Just m -> m
  Nothing -> unsafeCrashWith ("Puregrain.Cli.Pipeline.bayerOf: no Bayer map of side " <> show side)

-- | The library's settings for the options: the kernel, the gamma and the
-- | scan.
paramsOf :: forall r. { kernel :: KernelName, gamma :: GammaName, serpentine :: Boolean | r } -> DitherParams
paramsOf opts =
  defaults
    # withKernel (kernelOf opts.kernel)
    # withGamma (gammaOf opts.gamma)
    # withScan (if opts.serpentine then serpentine else raster)

kernelOf :: KernelName -> Kernel
kernelOf = case _ of
  FloydSteinberg -> floydSteinberg
  Atkinson -> atkinson
  JarvisJudiceNinke -> jarvisJudiceNinke
  Stucki -> stucki
  Burkes -> burkes
  Sierra3 -> sierra3
  Sierra2 -> sierra2
  SierraLite -> sierraLite
  Fan -> fan
  ShiauFan -> shiauFan
  ShiauFan2 -> shiauFan2
  NoDiffusion -> noDiffusion

paletteOf :: PaletteName -> NonEmptyArray RGB
paletteOf = case _ of
  BlackWhite -> blackWhite
  Websafe216 -> websafe216
  Cga16 -> cga16
  Ansi16 -> ansi16
  Ansi256 -> ansi256
  C64 -> c64
  ZxSpectrum -> zxSpectrum

gammaOf :: GammaName -> Gamma
gammaOf = case _ of
  GammaOff -> gammaOff
  Gamma1p2 -> gamma1p2
  Gamma1p5 -> gamma1p5
  Gamma1p8 -> gamma1p8
  GammaSrgb -> gammaSrgb

isNeutral :: RGB -> Boolean
isNeutral (RGB p) = p.r == p.g && p.g == p.b

-- | A neutral pixel at the color's gray, for `--gray`: by the library's
-- | `toGray`, luma on the stored values with `gammaOff`, as before, and
-- | with a curve the gray that gives off as much light as the color. A
-- | neutral pixel stays exactly as it is: with luma's weights, 65 of the
-- | 256 levels, 128 among them, would land one float step below, which
-- | changed 96% of a flat 128's dots with Floyd-Steinberg (same tone,
-- | another phase); `toGray` keeps them.
toNeutral :: Gamma -> RGB -> RGB
toNeutral gamma px = let v = toGray gamma px in RGB { r: v, g: v, b: v }
