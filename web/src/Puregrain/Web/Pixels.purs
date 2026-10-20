-- | A picture's pixels in the browser: RGBA bytes, row after row, in a
-- | `Uint8ClampedArray`, as a canvas's `ImageData` holds them. Rows are
-- | read and written one at a time, so the worker never holds the whole
-- | picture as PureScript values.
module Puregrain.Web.Pixels
  ( readRow
  , writeRgbRow
  , writeGrayRow
  , allNeutral
  , newPixels
  , copyPixels
  , transferable
  , toImageData
  ) where

import Prelude

import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Effect (Effect)
import Graphics.Canvas (ImageData)
import Puregrain (RGB)
import Web.Worker.Types (Transferable)

-- | The row `y` of a picture `width` pixels wide, as RGB values (alpha
-- | ignored).
foreign import readRow :: Uint8ClampedArray -> Int -> Int -> Effect (Array RGB)

-- | Writes the row `y`, each channel rounded and clamped to 0–255 as the
-- | CLI writes its PNGs, with alpha 255.
foreign import writeRgbRow :: Uint8ClampedArray -> Int -> Int -> Array RGB -> Effect Unit

-- | Writes the row `y` of gray values into all three channels.
foreign import writeGrayRow :: Uint8ClampedArray -> Int -> Int -> Array Number -> Effect Unit

-- | Whether every pixel has r = g = b.
foreign import allNeutral :: Uint8ClampedArray -> Effect Boolean

-- | Zeroed bytes, `length` of them.
foreign import newPixels :: Int -> Effect Uint8ClampedArray

foreign import copyPixels :: Uint8ClampedArray -> Effect Uint8ClampedArray

-- | The bytes' buffer, to transfer them in a message instead of copying.
foreign import transferable :: Uint8ClampedArray -> Transferable

-- | The bytes as an `ImageData` of that size, for a canvas.
foreign import toImageData :: Uint8ClampedArray -> Int -> Int -> Effect ImageData
