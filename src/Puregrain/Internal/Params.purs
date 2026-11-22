-- | The settings every driver shares, behind `Puregrain.Dither`'s opaque
-- | `DitherParams`. Internal: may change without notice.
-- |
-- | (The doc comments below the module's are what Pursuit shows, through
-- | `Puregrain.Dither`'s re-export.)
module Puregrain.Internal.Params
  ( DitherParams(..)
  , defaults
  , withKernel
  , withGamma
  , gammaOf
  , compileParams
  ) where

import Puregrain.Internal.Gamma (Gamma(..))
import Puregrain.Internal.Kernel (CompiledKernel, compileKernel)
import Puregrain.Kernel (Kernel, noDiffusion)

-- | How an image is dithered, apart from the quantizer: the kernel, where
-- | each pixel's error goes, and the gamma, in which light. Opaque: start
-- | from `defaults` and change one setting at a time with the `with…`
-- | functions, chained with `#`:
-- |
-- | ```purescript
-- | params = defaults # withKernel floydSteinberg # withGamma gammaSrgb
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
  }

-- | The settings to start from, each one neutral: no diffusion
-- | (`noDiffusion`), so each pixel is only quantized, and `gammaOff`.
-- | Dithering with them alone is plain quantizing, or pure ordered
-- | dithering with a quantizer from `Puregrain.Ordered`; add a kernel
-- | with `withKernel` for error diffusion.
defaults :: DitherParams
defaults = DitherParams { kernel: noDiffusion, gamma: Off }

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

-- | The gamma of the settings, for the drivers' conversion to light.
gammaOf :: DitherParams -> Gamma
gammaOf (DitherParams p) = p.gamma

-- | What the row code needs of the settings, compiled once per image.
compileParams :: DitherParams -> CompiledKernel
compileParams (DitherParams p) = compileKernel p.kernel
