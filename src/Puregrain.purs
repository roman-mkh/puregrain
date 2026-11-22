-- | Error-diffusion and ordered dithering, in one import. This module
-- | re-exports what a typical application needs:
-- |
-- | - `ditherImage`, which dithers an image in memory; `ditherRows`, which
-- |   dithers a lazy stream of rows, each when it's needed; and
-- |   `initDithering` with `ditherRow`, one row at a time from any source;
-- | - the kernels `floydSteinberg`, `atkinson`, `jarvisJudiceNinke`,
-- |   `stucki`, `burkes`, `sierra3`, `sierra2`, `sierraLite`, `fan`,
-- |   `shiauFan` and `shiauFan2`, and `noDiffusion` for none;
-- | - the quantizers `threshold`, `nearestLevel` with `evenRamp`, and
-- |   `perChannel` for color; `nearestColor` with the palette presets;
-- |   `bayer` and `ordered` for ordered dithering;
-- | - `ditherImageBy`, `ditherRowsBy` and `initDitheringBy`, the same
-- |   with their settings in a `DitherParams`, built from `defaults` with
-- |   `withKernel` and `withGamma`;
-- | - `ditherImageWith`, `ditherRowsWith` and `initDitheringWith`, the
-- |   same with a gamma curve, `gammaOff`, `gamma1p2`, `gamma1p5`,
-- |   `gamma1p8` or `gammaSrgb`, which says how the stored numbers turn
-- |   into light; and `toGray`, a color's gray by that curve;
-- | - the pixel types `RGB` and `RGBA`, and the types for signatures.
-- |
-- | Import it qualified, as names like `threshold` or `c64` are short:
-- |
-- | ```purescript
-- | import Puregrain as P
-- |
-- | dithered = P.ditherImage P.floydSteinberg (P.threshold 128.0) image
-- | ```
-- |
-- | The building blocks for your own variants (distance metrics, threshold
-- | maps, custom quantizers) are in the modules they come from:
-- | `Puregrain.Palette`, `Puregrain.Ordered`, `Puregrain.Quantize`,
-- | `Puregrain.Pixel`, `Puregrain.Kernel` and `Puregrain.Gamma`. Dithering with cells, as on
-- | the screens of 8-bit machines, is in `Puregrain.Cells` and
-- | `Puregrain.Machine.ZxSpectrum`, outside this module.
module Puregrain
  ( module Puregrain.Dither
  , module Puregrain.Gamma
  , module Puregrain.Kernel
  , module Puregrain.Ordered
  , module Puregrain.Palette
  , module Puregrain.Palette.Presets
  , module Puregrain.Pixel
  , module Puregrain.Quantize
  ) where

import Puregrain.Dither (DitherParams, Dithering, defaults, ditherImage, ditherImageBy, ditherImageWith, ditherRow, ditherRows, ditherRowsBy, ditherRowsWith, initDithering, initDitheringBy, initDitheringWith, withGamma, withKernel)
import Puregrain.Gamma (Gamma, gamma1p2, gamma1p5, gamma1p8, gammaOff, gammaSrgb, toGray)
import Puregrain.Kernel (Kernel, Offset, atkinson, burkes, fan, floydSteinberg, jarvisJudiceNinke, noDiffusion, shiauFan, shiauFan2, sierra2, sierra3, sierraLite, stucki)
import Puregrain.Ordered (ThresholdMap, bayer, ordered)
import Puregrain.Palette (nearestColor)
import Puregrain.Palette.Presets (ansi16, ansi256, blackWhite, c64, cga16, websafe216, zxSpectrum)
import Puregrain.Pixel (class ColorChannels, class MapChannels, class Scalable, Gray, RGB(..), RGBA(..))
import Puregrain.Quantize (Context, Quantize, evenRamp, nearestLevel, perChannel, quantize, quantizeWith, runQuantize, threshold)
