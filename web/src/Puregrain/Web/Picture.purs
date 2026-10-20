-- | Loading a picture in the browser: the browser decodes the file, and
-- | its pixels are read back from a canvas. It decodes without color
-- | conversion, so the stored values are the ones dithered, as in the CLI,
-- | and transparent parts are put onto white (decision 9 in
-- | web/ROADMAP.md).
module Puregrain.Web.Picture
  ( Picture
  , load
  , draw
  ) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.Int (toNumber)
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Graphics.Canvas (CanvasElement, CanvasImageSource, ImageData, drawImage, fillRect, getContext2D, getImageData, putImageData, setCanvasHeight, setCanvasWidth, setFillStyle)
import Unsafe.Coerce (unsafeCoerce)
import Web.File.File (File)
import Web.File.File as File
import Web.HTML.HTMLElement (HTMLElement)

-- | A loaded picture: the file's name, its size in pixels, and the pixels
-- | themselves as the canvas holds them, RGBA with alpha 255 everywhere
-- | after the flattening onto white.
type Picture = { name :: String, width :: Int, height :: Int, pixels :: ImageData }

foreign import data ImageBitmap :: Type

foreign import decodeImpl :: File -> Effect (Promise ImageBitmap)
foreign import bitmapWidth :: ImageBitmap -> Int
foreign import bitmapHeight :: ImageBitmap -> Int
foreign import closeBitmap :: ImageBitmap -> Effect Unit
foreign import newCanvas :: Effect CanvasElement

-- | Decodes the file and reads its pixels. Fails, in `Aff`, when the
-- | browser can't decode the file as a picture.
load :: File -> Aff Picture
load file = do
  bitmap <- toAffE (decodeImpl file)
  liftEffect do
    let
      width = bitmapWidth bitmap
      height = bitmapHeight bitmap
    canvas <- newCanvas
    setCanvasWidth canvas (toNumber width)
    setCanvasHeight canvas (toNumber height)
    ctx <- getContext2D canvas
    -- White first: a canvas loses the colors of fully transparent pixels.
    setFillStyle ctx "white"
    fillRect ctx { x: 0.0, y: 0.0, width: toNumber width, height: toNumber height }
    drawImage ctx (asImageSource bitmap) 0.0 0.0
    pixels <- getImageData ctx 0.0 0.0 (toNumber width) (toNumber height)
    closeBitmap bitmap
    pure { name: File.name file, width, height, pixels }

-- | Puts the pixels onto a canvas element of their size.
draw :: HTMLElement -> ImageData -> Effect Unit
draw element pixels = do
  ctx <- getContext2D (unsafeCoerce element :: CanvasElement)
  putImageData ctx pixels 0.0 0.0

-- | The canvas's `drawImage` takes an `ImageBitmap` too, not only the
-- | image sources the canvas package knows.
asImageSource :: ImageBitmap -> CanvasImageSource
asImageSource = unsafeCoerce
