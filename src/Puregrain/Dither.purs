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
module Puregrain.Dither
  ( ditherImage
  , ditherRows
  , Dithering
  , initDithering
  , ditherRow
  ) where

import Prelude

import Data.CatQueue (CatQueue)
import Data.Either (Either)
import Data.List.Lazy as LL
import Data.Tuple (Tuple(..))
import Puregrain.Internal.Image (ditherImageWith, ditherRowsWith)
import Puregrain.Internal.Kernel (CompiledKernel, compileKernel)
import Puregrain.Internal.Row (stepRow)
import Puregrain.Internal.State (DitherState, initState)
import Puregrain.Kernel (Kernel)
import Puregrain.Pixel (class Scalable)
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
ditherImage = ditherImageWith (Proxy :: Proxy CatQueue)

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
ditherRows = ditherRowsWith (Proxy :: Proxy CatQueue)

-- | An image being dithered one row at a time, for `ditherRow`: the
-- | kernel, the quantizer, and the error waiting for the rows still to
-- | come; `a` is the pixel type. Opaque.
-- |
-- | An immutable value: keep and reuse one, for an undo, say. Dithering a
-- | row from it again redoes that row's work, and no more.
newtype Dithering a = Dithering
  { compiled :: CompiledKernel
  , quantize :: Quantize a
  , state :: DitherState CatQueue a
  }

-- | The state before the first row, for `ditherRow`.
-- |
-- | - `Kernel`: where each pixel's error goes; `noDiffusion` for nowhere.
-- | - `Quantize a`: picks each pixel's output value.
-- |
-- | Computes nothing yet; the first row fixes the image's width.
initDithering :: forall a. Kernel -> Quantize a -> Dithering a
initDithering kernel quantize = Dithering { compiled, quantize, state: initState compiled }
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
  stepRow d.compiled d.quantize d.state pixels <#> \(Tuple state dithered) ->
    { row: dithered, next: Dithering d { state = state } }
