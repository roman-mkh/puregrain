-- | The settings as library values, as the CLI builds them from its
-- | options. `isNeutral`, `luma` and `toNeutral` are copied from the CLI's
-- | `Puregrain.Cli.Pipeline`, so both clients turn a picture gray alike;
-- | after v1 they're a candidate for the library (web/ROADMAP.md, phase 0
-- | results).
module Puregrain.Web.Dither
  ( Pipeline(..)
  , pipelineFor
  , kernelOf
  , paletteOf
  , isNeutral
  , luma
  , toNeutral
  ) where

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Partial.Unsafe (unsafeCrashWith)
import Puregrain (Kernel, Quantize, RGB(..), ThresholdMap, ansi16, ansi256, atkinson, bayer, blackWhite, c64, cga16, evenRamp, floydSteinberg, jarvisJudiceNinke, nearestColor, nearestLevel, noDiffusion, ordered, perChannel, threshold, websafe216, zxSpectrum)
import Puregrain.Web.Settings (Colors(..), KernelName(..), PaletteName(..), Settings)

-- | Dither in one gray channel, or in RGB.
data Pipeline
  = Gray (Quantize Number)
  | Color (Quantize RGB)

-- | The quantizer for the settings, as the CLI chooses it: a threshold
-- | always on gray; levels, with or without a Bayer map, on gray for a
-- | gray picture and per channel otherwise; a palette always on RGB.
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

kernelOf :: KernelName -> Kernel
kernelOf = case _ of
  NoDiffusion -> noDiffusion
  FloydSteinberg -> floydSteinberg
  Atkinson -> atkinson
  JarvisJudiceNinke -> jarvisJudiceNinke

paletteOf :: PaletteName -> NonEmptyArray RGB
paletteOf = case _ of
  BlackWhite -> blackWhite
  Websafe216 -> websafe216
  Cga16 -> cga16
  Ansi16 -> ansi16
  Ansi256 -> ansi256
  C64 -> c64
  ZxSpectrum -> zxSpectrum

-- | The settings offer only powers of 2, for which `bayer` always has a
-- | map.
bayerOf :: Int -> ThresholdMap
bayerOf side = case bayer side of
  Just m -> m
  Nothing -> unsafeCrashWith ("Puregrain.Web.Dither.bayerOf: no Bayer map of side " <> show side)

isNeutral :: RGB -> Boolean
isNeutral (RGB p) = p.r == p.g && p.g == p.b

-- | A pixel's gray value: exact for a neutral pixel, Rec. 601 luma
-- | (0.299 R + 0.587 G + 0.114 B) on the stored sRGB values otherwise, as
-- | in the CLI (see its `Puregrain.Cli.Pipeline.luma` for why exact).
luma :: RGB -> Number
luma px@(RGB p)
  | isNeutral px = p.r
  | otherwise = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b

toNeutral :: RGB -> RGB
toNeutral px = let v = luma px in RGB { r: v, g: v, b: v }
