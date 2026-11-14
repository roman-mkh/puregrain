-- | The settings as library values, as the CLI builds them from its
-- | options. A picture turns gray by the library's `toGray`, as in the
-- | CLI, so both clients turn it gray alike; `isNeutral` and `toNeutral`
-- | are the CLI's too. The machines' modules aren't in the `Puregrain`
-- | facade, so they're imported directly, as the CLI does.
module Puregrain.Web.Dither
  ( Pipeline(..)
  , pipelineFor
  , kernelOf
  , paletteOf
  , zxModeOf
  , gammaOf
  , isNeutral
  , toNeutral
  ) where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), maybe)
import Partial.Unsafe (unsafeCrashWith)
import Puregrain (Gamma, Kernel, Quantize, RGB(..), ThresholdMap, ansi16, ansi256, atkinson, bayer, blackWhite, burkes, c64, cga16, evenRamp, fan, floydSteinberg, gamma1p2, gamma1p5, gamma1p8, gammaOff, gammaSrgb, jarvisJudiceNinke, nearestColor, nearestLevel, noDiffusion, ordered, perChannel, shiauFan, shiauFan2, sierra2, sierra3, sierraLite, stucki, threshold, toGray, websafe216, zxSpectrum)
import Puregrain.Cells (CellMode, CellQuantizer, nearestInCell, orderedInCell)
import Puregrain.Machine.ZxSpectrum as Zx
import Puregrain.Web.Settings (Colors(..), GammaName(..), KernelName(..), MachineName, MachinePaletteName(..), PaletteName(..), Settings, Target(..))

-- | Dither in one gray channel, in RGB, or to a machine's screen (RGB,
-- | cell by cell, with the machine's palette and a rule inside the cells).
data Pipeline
  = Gray (Quantize Number)
  | Color (Quantize RGB)
  | Screen { machine :: MachineName, palette :: MachinePaletteName, rule :: CellQuantizer }

-- | The quantizer for the settings, as the CLI chooses it: a threshold
-- | always on gray; levels, with or without a Bayer map, on gray for a
-- | gray picture and per channel otherwise; a palette always on RGB; a
-- | machine's colors on RGB too, with the nearer of each cell's colors,
-- | or with a Bayer map ordered dithering inside the cells.
-- | `grayPicture` is true for an all-neutral picture, or when the settings
-- | turn it gray. `Nothing` for the original: nothing to dither.
pipelineFor :: Settings -> Boolean -> Maybe Pipeline
pipelineFor s grayPicture = case s.colors of
  Original -> Nothing
  Threshold t -> Just (Gray (threshold (toNumber t)))
  Levels n ->
    let
      scalar = case s.bayer of
        Nothing -> nearestLevel (evenRamp n)
        Just side -> ordered (bayerOf side) (evenRamp n)
    in
      Just (if grayPicture then Gray scalar else Color (perChannel scalar))
  Palette p -> Just (Color (nearestColor (paletteOf p)))
  MachineColors palette -> case s.target of
    Machine machine -> Just (Screen { machine, palette, rule: maybe nearestInCell (orderedInCell <<< bayerOf) s.bayer })
    -- The settings' rules rule these colors out for any screen.
    AnyScreen -> Nothing

kernelOf :: KernelName -> Kernel
kernelOf = case _ of
  NoDiffusion -> noDiffusion
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

paletteOf :: PaletteName -> NonEmptyArray RGB
paletteOf = case _ of
  BlackWhite -> blackWhite
  Websafe216 -> websafe216
  Cga16 -> cga16
  Ansi16 -> ansi16
  Ansi256 -> ansi256
  C64 -> c64
  ZxSpectrum -> zxSpectrum

-- | The ZX Spectrum's screen mode with these of its colors.
zxModeOf :: MachinePaletteName -> CellMode Zx.Attribute
zxModeOf = case _ of
  FullPalette -> Zx.screen
  NormalPalette -> Zx.normalScreen
  BrightPalette -> Zx.brightScreen

-- | The settings offer only powers of 2, for which `bayer` always has a
-- | map.
bayerOf :: Int -> ThresholdMap
bayerOf side = case bayer side of
  Just m -> m
  Nothing -> unsafeCrashWith ("Puregrain.Web.Dither.bayerOf: no Bayer map of side " <> show side)

gammaOf :: GammaName -> Gamma
gammaOf = case _ of
  GammaOff -> gammaOff
  Gamma1p2 -> gamma1p2
  Gamma1p5 -> gamma1p5
  Gamma1p8 -> gamma1p8
  GammaSrgb -> gammaSrgb

isNeutral :: RGB -> Boolean
isNeutral (RGB p) = p.r == p.g && p.g == p.b

-- | A neutral pixel at the color's gray, by the gamma, as the CLI's
-- | `toNeutral`: luma on the stored values with `gammaOff`, else the
-- | gray with the color's light; a neutral pixel stays exactly as it is.
toNeutral :: Gamma -> RGB -> RGB
toNeutral gamma px = let v = toGray gamma px in RGB { r: v, g: v, b: v }
