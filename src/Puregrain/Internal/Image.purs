-- | The two drivers that run the diffusion over a whole image, row by row,
-- | with any `Fifo` backend and any conversion to light: `ditherImageVia`
-- | over an array of rows (all at once) and `ditherRowsVia` over a lazy
-- | list of rows (each when asked for). Both drive the same `stepRow`, so
-- | they give the same result; a row of a different length, a `Left` from
-- | `stepRow`, becomes a runtime error here, since neither result type can
-- | carry it.
-- | Internal: `Puregrain.Dither` exports them with the production backend;
-- | the tests use them to check every backend against a reference.
module Puregrain.Internal.Image
  ( ditherImageVia
  , ditherRowsVia
  , rowsIn
  , rowsOut
  ) where

import Prelude

import Data.Lazy (defer)
import Data.List.Lazy as LL
import Data.List.Lazy.Types (List(..), Step(..))
import Data.Traversable (mapAccumL)
import Data.Tuple (Tuple(..))
import Puregrain.Internal.Fifo (class Fifo)
import Puregrain.Internal.Gamma (Conversion, isOff)
import Puregrain.Internal.Kernel (compileKernel)
import Puregrain.Internal.Quantize (Quantize, quantizerFor)
import Puregrain.Internal.Row (orStop, stepRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class Scalable)
import Type.Proxy (Proxy)

-- | A row converted to light before it's dithered, or left as it is when
-- | the conversion is off.
rowsIn :: forall a. Conversion a -> Array a -> Array a
rowsIn conversion = if isOff conversion.gamma then identity else map conversion.toLight

-- | A dithered row converted back from light, or left as it is when the
-- | conversion is off.
rowsOut :: forall a. Conversion a -> Array a -> Array a
rowsOut conversion = if isOff conversion.gamma then identity else map conversion.fromLight

-- | An image in memory: a strict fold over the array of rows.
ditherImageVia
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => Proxy f
  -> Conversion a
  -> Kernel
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
ditherImageVia _ conversion kernel quantize rows =
  (mapAccumL next (initState compiled :: DitherState f a) rows).value
  where
    compiled = compileKernel kernel
    -- resolved once, here, for every pixel of the image
    quantizer = quantizerFor conversion quantize
    toLight = rowsIn conversion
    fromLight = rowsOut conversion

    next state row =
      let Tuple state' quantizedRow = orStop (stepRow compiled quantizer state (toLight row))
      in { accum: state', value: fromLight quantizedRow }

-- | A stream of rows: a lazy unfold over the list of rows.
ditherRowsVia
  :: forall f a
   . Fifo f
  => Ring a
  => Scalable a
  => Proxy f
  -> Conversion a
  -> Kernel
  -> Quantize a
  -> LL.List (Array a)
  -> LL.List (Array a)
ditherRowsVia _ conversion kernel quantize rows =
  go (initState compiled) rows
  where
    compiled = compileKernel kernel
    -- resolved once, when the stream is set up, as the kernel is compiled;
    -- neither reads a row
    quantizer = quantizerFor conversion quantize
    toLight = rowsIn conversion
    fromLight = rowsOut conversion

    -- All the work happens inside `defer`: a row is read and dithered only
    -- when its cell is forced. (With the `let` outside it, as before
    -- 2026-10-04, a strict `let` dithered each row one cell early.)
    go :: DitherState f a -> LL.List (Array a) -> LL.List (Array a)
    go state remainingRows = List $ defer \_ ->
      case LL.step remainingRows of
        Nil -> Nil
        Cons row rest ->
          let Tuple state' quantizedRow = orStop (stepRow compiled quantizer state (toLight row))
          in Cons (fromLight quantizedRow) (go state' rest)
