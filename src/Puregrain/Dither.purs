-- | Dithering a whole image, in three ways that give the same rows for the
-- | same input, with a kernel (`Puregrain.Kernel`) and a quantizer
-- | (`Puregrain.Quantize`, `Puregrain.Palette`, `Puregrain.Ordered`):
-- |
-- | - `ditherImage`: an image in memory, all at once;
-- | - `ditherRows`: a lazy stream of rows, each dithered when it's needed;
-- | - `initDithering` and `ditherRow`: one row at a time, with you running
-- |   the loop. For rows that come from effects, such as a network stream
-- |   or a file read piece by piece:
-- |
-- | ```purescript
-- | -- readRow and writeRow are your own, here in Aff
-- | loop :: Dithering Number -> Aff Unit
-- | loop dithering = readRow >>= case _ of
-- |   Nothing -> pure unit
-- |   Just row -> case ditherRow dithering row of
-- |     Left problem -> throwError (error problem)
-- |     Right { row: dithered, next } -> writeRow dithered *> loop next
-- |
-- | main = launchAff_ (loop (initDithering floydSteinberg (threshold 128.0)))
-- | ```
-- |
-- | `Aff` keeps such a loop from growing the stack, however long the
-- | stream; in `Effect`, write it with `tailRecM`.
-- |
-- | Each takes its settings in one of two ways:
-- |
-- | - `ditherImageBy`, `ditherRowsBy` and `initDitheringBy` take a
-- |   `DitherParams`: the kernel, the gamma and any later setting, built
-- |   from `defaults` with the `with…` functions;
-- | - `ditherImage`, `ditherRows` and `initDithering` take just a kernel,
-- |   and their twins `ditherImageWith`, `ditherRowsWith` and
-- |   `initDitheringWith` a `Puregrain.Gamma.Gamma` and a kernel: shorthands
-- |   for the `…By` drivers with those settings.
-- |
-- | ```purescript
-- | -- the same rows, twice
-- | ditherImageBy (defaults # withKernel floydSteinberg # withGamma gammaSrgb) (threshold 128.0) image
-- | ditherImageWith gammaSrgb floydSteinberg (threshold 128.0) image
-- | ```
-- |
-- | A gamma keeps the amount of light, by that curve, rather than the
-- | average of the stored numbers; `gammaOff` is the plain result. Which
-- | gamma for which view:
-- | [docs/gamma.md](https://github.com/roman-mkh/puregrain/blob/master/docs/gamma.md).
module Puregrain.Dither
  ( module Exports
  , ditherImageBy
  , ditherImage
  , ditherImageWith
  , ditherRowsBy
  , ditherRows
  , ditherRowsWith
  , Dithering
  , initDitheringBy
  , initDithering
  , initDitheringWith
  , ditherRow
  ) where

import Prelude

import Data.CatQueue (CatQueue)
import Data.Either (Either)
import Data.List.Lazy as LL
import Data.Tuple (Tuple(..))
import Puregrain.Internal.Gamma (Conversion, Gamma, conversionFor, noConversion)
import Puregrain.Internal.Image (ditherImageVia, ditherRowsVia, rowsIn, rowsOut)
import Puregrain.Internal.Kernel (CompiledKernel)
import Puregrain.Internal.Params (DitherParams, defaults, withGamma, withKernel) as Exports
import Puregrain.Internal.Params (DitherParams, compileParams, defaults, gammaOf, withGamma, withKernel)
import Puregrain.Internal.Quantize (Quantizer, quantizerFor)
import Puregrain.Internal.Row (stepRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class ColorChannels, class Scalable)
import Puregrain.Quantize (Quantize)
import Type.Proxy (Proxy(..))
-- | Dithers an image in memory, with the settings given.
-- |
-- | - `a`: the pixel type, `Number` for gray, `RGB` or `RGBA`; any type
-- |   with `Ring`, `Scalable` and `ColorChannels` works.
-- | - `DitherParams`: the kernel and the gamma, from `defaults` and the
-- |   `with…` functions.
-- | - `Quantize a`: picks each pixel's output value.
-- | - `Array (Array a)`: the image, rows top to bottom, each left to right,
-- |   all of the same length.
-- |
-- | Returns the dithered image, all at once, as stored values. Under a
-- | gamma other than `gammaOff`, each row is taken to light, dithered
-- | there, and brought back: the error and the amounts of light (ordered
-- | dithering's patterns) are in light; the choices of the nearest level
-- | or color stay on stored values, as the eye sees them; a level or a
-- | palette color of whole numbers comes back exactly. Stops with an error
-- | naming a row whose length differs from the first row's.
-- |
-- | ```purescript
-- | ditherImageBy (defaults # withKernel floydSteinberg # withGamma gammaSrgb) (threshold 128.0) image
-- | ```
ditherImageBy
  :: forall a
   . Ring a
  => Scalable a
  => ColorChannels a
  => DitherParams
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
ditherImageBy params = ditherImageVia (Proxy :: Proxy CatQueue) (conversionFor (gammaOf params)) (compileParams params)

-- | Dithers an image in memory, with a kernel and no other setting.
-- |
-- | - `a`: the pixel type, `Number` for gray, `RGB` or `RGBA`; any type
-- |   with `Ring` and `Scalable` works, `ColorChannels` not needed.
-- | - `Kernel`: where each pixel's error goes; `noDiffusion` for nowhere.
-- | - `Quantize a`: picks each pixel's output value.
-- | - `Array (Array a)`: the image, as for `ditherImageBy`.
-- |
-- | Returns what `ditherImageBy (defaults # withKernel kernel)` returns.
ditherImage
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
ditherImage kernel = ditherImageVia (Proxy :: Proxy CatQueue) noConversion (compileParams (defaults # withKernel kernel))

-- | Dithers an image in memory, with a gamma and a kernel.
-- |
-- | - `a`: as for `ditherImageBy`.
-- | - `Gamma`: how the stored numbers turn into light: `gammaOff`, the
-- |   same as `ditherImage`, or `gamma1p2`, `gamma1p5`, `gamma1p8` or
-- |   `gammaSrgb` (linear light).
-- | - `Kernel`, `Quantize a`, `Array (Array a)`: as for `ditherImage`.
-- |
-- | Returns what `ditherImageBy (defaults # withKernel kernel # withGamma
-- | gamma)` returns.
-- |
-- | ```purescript
-- | ditherImageWith gammaSrgb floydSteinberg (threshold 128.0) image
-- | ```
ditherImageWith
  :: forall a
   . Ring a
  => Scalable a
  => ColorChannels a
  => Gamma
  -> Kernel
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
ditherImageWith gamma kernel = ditherImageBy (defaults # withKernel kernel # withGamma gamma)

-- | Dithers a lazy stream of rows, with the settings given.
-- |
-- | - `a`, `DitherParams` and `Quantize a`: as for `ditherImageBy`.
-- | - `LL.List (Array a)`: the rows, top to bottom, all of the same length;
-- |   the list may be endless.
-- |
-- | Returns the dithered rows as a lazy list, the same rows as
-- | `ditherImageBy`. Each row is read and dithered only when its result is
-- | first needed, so only the rows in flight are in memory. At a row whose
-- | length differs from the first row's, it stops with an error naming
-- | the row; the rows before it have come out.
ditherRowsBy
  :: forall a
   . Ring a
  => Scalable a
  => ColorChannels a
  => DitherParams
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherRowsBy params = ditherRowsVia (Proxy :: Proxy CatQueue) (conversionFor (gammaOf params)) (compileParams params)

-- | Dithers a lazy stream of rows, with a kernel and no other setting.
-- |
-- | - `a`, `Kernel` and `Quantize a`: as for `ditherImage`.
-- | - `LL.List (Array a)`: the rows, as for `ditherRowsBy`.
-- |
-- | Returns what `ditherRowsBy (defaults # withKernel kernel)` returns.
ditherRows
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherRows kernel = ditherRowsVia (Proxy :: Proxy CatQueue) noConversion (compileParams (defaults # withKernel kernel))

-- | Dithers a lazy stream of rows, with a gamma and a kernel.
-- |
-- | - `a` and `Gamma`: as for `ditherImageWith`.
-- | - `Kernel`, `Quantize a`, `LL.List (Array a)`: as for `ditherRows`.
-- |
-- | Returns what `ditherRowsBy (defaults # withKernel kernel # withGamma
-- | gamma)` returns.
ditherRowsWith
  :: forall a
   . Ring a
  => Scalable a
  => ColorChannels a
  => Gamma
  -> Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherRowsWith gamma kernel = ditherRowsBy (defaults # withKernel kernel # withGamma gamma)

-- | An image being dithered one row at a time, for `ditherRow`: the
-- | settings, the quantizer, and the error waiting for the rows still to
-- | come; `a` is the pixel type. Opaque.
-- |
-- | An immutable value: keep and reuse one, for an undo, say. Dithering a
-- | row from it again redoes that row's work, and no more.
-- The quantizer is kept resolved, once for the whole image, with the
-- conversion that brings each row to light and back.
newtype Dithering a = Dithering
  { compiled :: CompiledKernel
  , quantizer :: Quantizer a
  , conversion :: Conversion a
  , state :: DitherState CatQueue a
  }

-- | The state before the first row, for `ditherRow`, with the settings
-- | given.
-- |
-- | - `a`, `DitherParams` and `Quantize a`: as for `ditherImageBy`.
-- |
-- | Dithers nothing yet; the first row fixes the image's width. `ditherRow`
-- | then gives the same rows as `ditherImageBy`, each as stored values.
initDitheringBy :: forall a. ColorChannels a => DitherParams -> Quantize a -> Dithering a
initDitheringBy params = initDitheringVia (conversionFor (gammaOf params)) (compileParams params)

-- | The state before the first row, for `ditherRow`, with a kernel and no
-- | other setting.
-- |
-- | - `Kernel` and `Quantize a`: as for `ditherImage`.
-- |
-- | Returns what `initDitheringBy (defaults # withKernel kernel)` returns.
initDithering :: forall a. Kernel -> Quantize a -> Dithering a
initDithering kernel = initDitheringVia noConversion (compileParams (defaults # withKernel kernel))

-- | The state before the first row, for `ditherRow`, with a gamma and a
-- | kernel.
-- |
-- | - `a` and `Gamma`: as for `ditherImageWith`.
-- | - `Kernel` and `Quantize a`: as for `initDithering`.
-- |
-- | Returns what `initDitheringBy (defaults # withKernel kernel # withGamma
-- | gamma)` returns.
initDitheringWith :: forall a. ColorChannels a => Gamma -> Kernel -> Quantize a -> Dithering a
initDitheringWith gamma kernel = initDitheringBy (defaults # withKernel kernel # withGamma gamma)

initDitheringVia :: forall a. Conversion a -> CompiledKernel -> Quantize a -> Dithering a
initDitheringVia conversion compiled quantize =
  Dithering { compiled, quantizer: quantizerFor conversion quantize, conversion, state: initState compiled }

-- | Dithers the next row.
-- |
-- | - `Dithering a`: the state, from `initDitheringBy`, `initDithering`,
-- |   `initDitheringWith` or the previous row.
-- | - `Array a`: the row, as long as the first one.
-- |
-- | Returns the dithered row and the state for the next one: the same rows
-- | as the matching `ditherImage…`. `Left`, with a message naming the row,
-- | for a row of a different length; the state passed in is untouched, so
-- | you can carry on with a corrected row.
ditherRow
  :: forall a
   . Ring a
  => Scalable a
  => Dithering a
  -> Array a
  -> Either String { row :: Array a, next :: Dithering a }
ditherRow (Dithering d) pixels =
  stepRow d.compiled d.quantizer d.state (rowsIn d.conversion pixels) <#> \(Tuple state dithered) ->
    { row: rowsOut d.conversion dithered, next: Dithering d { state = state } }
