-- | The settings every driver shares, behind `Puregrain.Dither`'s opaque
-- | `DitherParams`, and their compiled form. Internal: may change without
-- | notice.
-- |
-- | (The doc comments below the module's are what Pursuit shows, through
-- | `Puregrain.Dither`'s re-export.)
module Puregrain.Internal.Params
  ( DitherParams(..)
  , Scan(..)
  , defaults
  , withKernel
  , withGamma
  , withScan
  , raster
  , serpentine
  , gammaOf
  , CompiledParams
  , compileParams
  , rightToLeft
  ) where

import Data.Int (odd)
import Puregrain.Internal.Gamma (Gamma(..))
import Puregrain.Internal.Kernel (CompiledKernel, compileKernel)
import Puregrain.Kernel (Kernel, noDiffusion)

-- | How an image is dithered, apart from the quantizer: the kernel, where
-- | each pixel's error goes; the gamma, in which light; and the scan, the
-- | order the pixels are visited in. Opaque: start from `defaults` and
-- | change one setting at a time with the `with…` functions, chained with
-- | `#`:
-- |
-- | ```purescript
-- | params = defaults # withKernel floydSteinberg # withGamma gammaSrgb # withScan serpentine
-- |
-- | dithered = ditherImageBy params (threshold 128.0) image
-- | ```
-- |
-- | The order of the `with…` calls doesn't matter; a later call of the
-- | same one replaces the earlier setting. The quantizer is an argument of
-- | its own, since its type depends on the driver: a `Quantize a` for
-- | `ditherImageBy`, a cell rule for `Puregrain.Cells.ditherCellsBy`.
-- Every setter changes one field only, so they commute. A rule between
-- fields (a method that needs a scan of its own, say) belongs where the
-- drivers read them, `compileParams`, not in a setter. The quantizer stays
-- out so the compiler keeps the drivers' branches apart: inside, it would
-- need a type parameter and a second params type for the cells, or a check
-- at run time.
newtype DitherParams = DitherParams
  { kernel :: Kernel
  , gamma :: Gamma
  , scan :: Scan
  }

-- | The order the pixels are visited in, for `withScan`: `raster` or
-- | `serpentine`. Opaque.
-- Opaque, as `Gamma` is, so another order would be another value, and
-- no caller's pattern match could break. No instances yet (start closed).
data Scan = Raster | Serpentine

-- | The settings to start from, each one neutral: no diffusion
-- | (`noDiffusion`), so each pixel is only quantized; `gammaOff`; and
-- | `raster`, every row left to right. Dithering with them alone is plain
-- | quantizing, or pure ordered dithering with a quantizer from
-- | `Puregrain.Ordered`; add a kernel with `withKernel` for error
-- | diffusion.
defaults :: DitherParams
defaults = DitherParams { kernel: noDiffusion, gamma: Off, scan: Raster }

-- | Sets the kernel.
-- |
-- | - `Kernel`: where each pixel's error goes, from `Puregrain.Kernel`;
-- |   `noDiffusion` for nowhere.
-- | - `DitherParams`: the settings to change.
-- |
-- | Returns the settings with that kernel, the others unchanged.
withKernel :: Kernel -> DitherParams -> DitherParams
withKernel kernel (DitherParams p) = DitherParams p { kernel = kernel }

-- | Sets the gamma.
-- |
-- | - `Gamma`: how the stored numbers turn into light, from
-- |   `Puregrain.Gamma`: `gammaOff`, `gamma1p2`, `gamma1p5`, `gamma1p8` or
-- |   `gammaSrgb`. Which for which view:
-- |   [docs/gamma.md](https://github.com/roman-mkh/puregrain/blob/master/docs/gamma.md).
-- | - `DitherParams`: the settings to change.
-- |
-- | Returns the settings with that gamma, the others unchanged.
withGamma :: Gamma -> DitherParams -> DitherParams
withGamma gamma (DitherParams p) = DitherParams p { gamma = gamma }

-- | Sets the scan, the order the pixels are visited in.
-- |
-- | - `Scan`: `raster`, every row left to right (the default), or
-- |   `serpentine`, the rows alternating.
-- | - `DitherParams`: the settings to change.
-- |
-- | Returns the settings with that scan, the others unchanged.
withScan :: Scan -> DitherParams -> DitherParams
withScan scan (DitherParams p) = DitherParams p { scan = scan }

-- | Every row left to right, top to bottom: the default.
raster :: Scan
raster = Raster

-- | Serpentine scanning: the rows alternate, the first (row 0) left to
-- | right, the second right to left, and so on, top to bottom. On a row
-- | scanned right to left the kernel is mirrored, so each pixel's error
-- | still goes to pixels not yet processed: an offset's `dx` then counts
-- | to the left. It's the usual remedy for the patterns error diffusion
-- | draws when every row is scanned the same way.
-- |
-- | Each pixel's quantizer still gets its own position, counted from the
-- | image's left and top edges, so ordered dithering and machine cells
-- | work as with `raster`. With `noDiffusion` it changes nothing.
serpentine :: Scan
serpentine = Serpentine

-- | The gamma of the settings, for the drivers' conversion to light.
gammaOf :: DitherParams -> Gamma
gammaOf (DitherParams p) = p.gamma

-- | What the row code needs of the settings, compiled once per image: the
-- | kernel's offsets sorted by row (`CompiledKernel`), and the scan. The
-- | kernel's compiled form stays apart from the scan, since the scan isn't
-- | a property of the kernel: the per-pixel `step` needs only the kernel.
type CompiledParams =
  { kernel :: CompiledKernel
  , scan :: Scan
  }

compileParams :: DitherParams -> CompiledParams
compileParams (DitherParams p) = { kernel: compileKernel p.kernel, scan: p.scan }

-- | Whether row `y` (counted from 0, the image's top) is scanned right to
-- | left. Not stored anywhere: every row works it out from its own index,
-- | `DitherState.nextRow`, so it can't disagree with the `y` the quantizer
-- | sees.
rightToLeft :: Scan -> Int -> Boolean
rightToLeft scan y = case scan of
  Raster -> false
  Serpentine -> odd y
