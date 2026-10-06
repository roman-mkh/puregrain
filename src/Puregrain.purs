-- | Error-diffusion and ordered dithering, in one import. This module
-- | re-exports what a typical application needs:
-- |
-- | - `ditherImage`, which dithers an image in memory, and `ditherRows`,
-- |   which dithers a lazy stream of rows, each when it's needed;
-- | - the kernels `floydSteinberg`, `atkinson` and `jarvisJudiceNinke`, and
-- |   `noDiffusion` for none;
-- | - the quantizers `threshold`, `nearestLevel` with `evenRamp`, and
-- |   `perChannel` for color; `nearestColor` with the palette presets;
-- |   `bayer` and `ordered` for ordered dithering;
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
-- | `Puregrain.Pixel` and `Puregrain.Kernel`.
module Puregrain
  ( module Puregrain.Dither
  , module Puregrain.Kernel
  , module Puregrain.Ordered
  , module Puregrain.Palette
  , module Puregrain.Palette.Presets
  , module Puregrain.Pixel
  , module Puregrain.Quantize
  ) where

import Puregrain.Dither (ditherImage, ditherRows)
import Puregrain.Kernel (Kernel, Offset, atkinson, floydSteinberg, jarvisJudiceNinke, noDiffusion)
import Puregrain.Ordered (ThresholdMap, bayer, ordered)
import Puregrain.Palette (nearestColor)
import Puregrain.Palette.Presets (ansi16, ansi256, blackWhite, c64, cga16, websafe216, zxSpectrum)
import Puregrain.Pixel (class MapChannels, class Scalable, Gray, RGB(..), RGBA(..))
import Puregrain.Quantize (Context, Quantize, evenRamp, nearestLevel, perChannel, quantize, quantizeWith, runQuantize, threshold)
