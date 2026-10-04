-- | The CLI's decisions, as pure functions: which kind of dithering a
-- | command line asks for, and how a color pixel becomes gray. Kept out of
-- | `Puregrain.Cli.Main` (which only does I/O) so they can be tested.
module Puregrain.Cli.Pipeline
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
import Data.Maybe (Maybe(..))
import Puregrain (Kernel, Quantize, RGB(..), ThresholdMap, ansi16, ansi256, atkinson, bayer, blackWhite, c64, cga16, evenRamp, floydSteinberg, jarvisJudiceNinke, nearestColor, nearestLevel, ordered, perChannel, threshold, websafe216, zxSpectrum)
import Partial.Unsafe (unsafeCrashWith)
import Puregrain.Cli.Options (KernelName(..), PaletteName(..), QuantizerChoice(..))

-- | Dither in one gray channel, or in RGB.
data Pipeline = Gray (Quantize Number) | Color (Quantize RGB)

-- | A threshold always runs on gray. Levels, with or without `--bayer`,
-- | run on gray when the image is gray, and per channel (scalarED)
-- | otherwise. A palette always runs on RGB (vectorED) — its colors
-- | needn't be gray, even for a gray input. `grayImage` is true for an
-- | all-neutral input, or after `--gray`. This is the table in
-- | cli/README.md, "How the output is chosen".
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

-- | The `--bayer` option only accepts powers of 2, for which `bayer`
-- | always has a map.
bayerOf :: Int -> ThresholdMap
bayerOf side = case bayer side of
  Just m -> m
  Nothing -> unsafeCrashWith ("Puregrain.Cli.Pipeline.bayerOf: no Bayer map of side " <> show side)

kernelOf :: KernelName -> Kernel
kernelOf = case _ of
  FloydSteinberg -> floydSteinberg
  Atkinson -> atkinson
  JarvisJudiceNinke -> jarvisJudiceNinke
  NoDiffusion -> []

paletteOf :: PaletteName -> NonEmptyArray RGB
paletteOf = case _ of
  BlackWhite -> blackWhite
  Websafe216 -> websafe216
  Cga16 -> cga16
  Ansi16 -> ansi16
  Ansi256 -> ansi256
  C64 -> c64
  ZxSpectrum -> zxSpectrum

isNeutral :: RGB -> Boolean
isNeutral (RGB p) = p.r == p.g && p.g == p.b

-- | A pixel's gray value. Exact for a neutral pixel: Rec. 601 weights
-- | applied to r = g = b = v land one float step below v for 65 of the
-- | 256 levels, 128 among them. That only changes a decision where the
-- | incoming error is exactly zero, such as an image's first pixel, but
-- | error diffusion then carries the flipped dot into a differently phased
-- | pattern: on a flat 128 image, 96% of the output differed from the
-- | exact result (same tone, 50.1% white either way). Colored pixels get
-- | Rec. 601 luma (0.299 R + 0.587 G + 0.114 B) on the stored sRGB values,
-- | as the old JS CLI did.
luma :: RGB -> Number
luma px@(RGB p)
  | isNeutral px = p.r
  | otherwise = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b

toNeutral :: RGB -> RGB
toNeutral px = let v = luma px in RGB { r: v, g: v, b: v }
