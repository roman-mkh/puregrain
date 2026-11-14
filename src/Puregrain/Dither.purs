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
-- | Each has a twin that takes a `Puregrain.Gamma.Gamma` first:
-- | `ditherImageWith`, `ditherRowsWith` and `initDitheringWith`. They keep
-- | the amount of light, by that curve, rather than the average of the
-- | stored numbers; with `gammaOff` they're the same as the plain ones.
module Puregrain.Dither
  ( ditherImage
  , ditherImageWith
  , ditherRows
  , ditherRowsWith
  , Dithering
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
import Puregrain.Internal.Kernel (CompiledKernel, compileKernel)
import Puregrain.Internal.Quantize (Quantizer, quantizerFor)
import Puregrain.Internal.Row (stepRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class ColorChannels, class Scalable)
import Puregrain.Quantize (Quantize)
import Type.Proxy (Proxy(..))

-- | Dithers an image in memory.
-- |
-- | - `a`: the pixel type, `Number` for gray, `RGB` or `RGBA`; any type
-- |   with `Ring` and `Scalable` works.
-- | - `Kernel`: where each pixel's error goes; `noDiffusion` for nowhere.
-- | - `Quantize a`: picks each pixel's output value.
-- | - `Array (Array a)`: the image, rows top to bottom, each left to right,
-- |   all of the same length.
-- |
-- | Returns the dithered image, all at once. Stops with an error naming a
-- | row whose length differs from the first row's.
ditherImage
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
ditherImage = ditherImageVia (Proxy :: Proxy CatQueue) noConversion

-- | Dithers an image in memory, keeping the amount of light the curve
-- | gives each value rather than the average of the stored numbers.
-- |
-- | - `a`: the pixel type, `Number`, `RGB` or `RGBA`; any type with `Ring`,
-- |   `Scalable` and `ColorChannels` works.
-- | - `Gamma`: how the stored numbers turn into light: `gammaOff`, the
-- |   same as `ditherImage`, or `gamma1p2`, `gamma1p5`, `gamma1p8` or
-- |   `gammaSrgb` (linear light).
-- | - `Kernel`, `Quantize a`, `Array (Array a)`: as for `ditherImage`.
-- |
-- | Returns the dithered image as stored values: each row is taken to
-- | light, dithered there, and brought back. The error and the amounts of
-- | light (ordered dithering's patterns) are in light; the choices of the
-- | nearest level or color stay on stored values, as the eye sees them; a
-- | level or a palette color of whole numbers comes back exactly. Stops
-- | with an error naming a row whose length differs from the first row's.
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
ditherImageWith gamma = ditherImageVia (Proxy :: Proxy CatQueue) (conversionFor gamma)

-- | Dithers a lazy stream of rows.
-- |
-- | - `a`, `Kernel` and `Quantize a`: as for `ditherImage`.
-- | - `LL.List (Array a)`: the rows, top to bottom, all of the same length;
-- |   the list may be endless.
-- |
-- | Returns the dithered rows as a lazy list, the same rows as
-- | `ditherImage`. Each row is read and dithered only when its result is
-- | first needed, so only the rows in flight are in memory. At a row whose
-- | length differs from the first row's, it stops with an error naming
-- | the row; the rows before it have come out.
ditherRows
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherRows = ditherRowsVia (Proxy :: Proxy CatQueue) noConversion

-- | Dithers a lazy stream of rows, keeping the amount of light the curve
-- | gives each value.
-- |
-- | - `a` and `Gamma`: as for `ditherImageWith`.
-- | - `Kernel`, `Quantize a`, `LL.List (Array a)`: as for `ditherRows`.
-- |
-- | Returns the dithered rows as a lazy list, the same rows as
-- | `ditherImageWith`, each read and dithered when it's first needed.
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
ditherRowsWith gamma = ditherRowsVia (Proxy :: Proxy CatQueue) (conversionFor gamma)

-- | An image being dithered one row at a time, for `ditherRow`: the
-- | kernel, the quantizer, and the error waiting for the rows still to
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

-- | The state before the first row, for `ditherRow`.
-- |
-- | - `Kernel`: where each pixel's error goes; `noDiffusion` for nowhere.
-- | - `Quantize a`: picks each pixel's output value.
-- |
-- | Dithers nothing yet; the first row fixes the image's width.
initDithering :: forall a. Kernel -> Quantize a -> Dithering a
initDithering = initDitheringVia noConversion

-- | The state before the first row, for `ditherRow`, keeping the amount
-- | of light the curve gives each value.
-- |
-- | - `a` and `Gamma`: as for `ditherImageWith`.
-- | - `Kernel` and `Quantize a`: as for `initDithering`.
-- |
-- | `ditherRow` then gives the same rows as `ditherImageWith`, each as
-- | stored values.
initDitheringWith :: forall a. ColorChannels a => Gamma -> Kernel -> Quantize a -> Dithering a
initDitheringWith gamma = initDitheringVia (conversionFor gamma)

initDitheringVia :: forall a. Conversion a -> Kernel -> Quantize a -> Dithering a
initDitheringVia conversion kernel quantize =
  Dithering { compiled, quantizer: quantizerFor conversion quantize, conversion, state: initState compiled }
  where
    compiled = compileKernel kernel

-- | Dithers the next row.
-- |
-- | - `Dithering a`: the state, from `initDithering` or the previous row.
-- | - `Array a`: the row, as long as the first one.
-- |
-- | Returns the dithered row and the state for the next one: the same rows
-- | as `ditherImage`. `Left`, with a message naming the row, for a row of a
-- | different length; the state passed in is untouched, so you can carry
-- | on with a corrected row.
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
