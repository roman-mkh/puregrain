-- | Loading a picture in the browser: the browser decodes the file, and
-- | its pixels are read back. It decodes without color conversion, so the
-- | stored values are the ones dithered, as in the CLI (decision 9 in
-- | web/ROADMAP.md). The pixels are read with their transparency, exactly
-- | (decision 27): a 2D canvas gives an opaque picture's values exactly,
-- | but keeps colors premultiplied by alpha, which rounds semi-transparent
-- | ones, so a picture with transparency is read again through WebGL.
module Puregrain.Web.Picture
  ( Picture
  , load
  , draw
  ) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff)
import Effect.Class (liftEffect)
import Graphics.Canvas (CanvasElement, CanvasImageSource, ImageData, drawImage, getContext2D, getImageData, imageDataBuffer, putImageData, setCanvasHeight, setCanvasWidth)
import Puregrain.Web.Prepare (hasTransparency)
import Unsafe.Coerce (unsafeCoerce)
import Web.File.File (File)
import Web.File.File as File
import Web.HTML.HTMLElement (HTMLElement)

-- | A loaded picture: the file's name, its size in pixels, and its RGBA
-- | bytes as stored. `transparent` when some pixel isn't fully opaque;
-- | `exact` unless such a picture had to be read from a 2D canvas, without
-- | WebGL, which rounds its semi-transparent colors.
type Picture =
  { name :: String
  , width :: Int
  , height :: Int
  , pixels :: Uint8ClampedArray
  , transparent :: Boolean
  , exact :: Boolean
  }

foreign import data ImageBitmap :: Type

foreign import decodeImpl :: File -> Effect (Promise ImageBitmap)
foreign import bitmapWidth :: ImageBitmap -> Int
foreign import bitmapHeight :: ImageBitmap -> Int
foreign import closeBitmap :: ImageBitmap -> Effect Unit
foreign import newCanvas :: Effect CanvasElement
foreign import exactRgbaImpl
  :: (Uint8ClampedArray -> Maybe Uint8ClampedArray)
  -> Maybe Uint8ClampedArray
  -> ImageBitmap
  -> Effect (Maybe Uint8ClampedArray)

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
    drawImage ctx (asImageSource bitmap) 0.0 0.0
    fromCanvas <- imageDataBuffer <$> getImageData ctx 0.0 0.0 (toNumber width) (toNumber height)
    transparent <- hasTransparency fromCanvas
    exactly <- if transparent then exactRgbaImpl Just Nothing bitmap else pure Nothing
    closeBitmap bitmap
    pure case exactly of
      Just pixels -> { name: File.name file, width, height, pixels, transparent, exact: true }
      Nothing -> { name: File.name file, width, height, pixels: fromCanvas, transparent, exact: not transparent }

-- | Puts the pixels onto a canvas element of their size.
draw :: HTMLElement -> ImageData -> Effect Unit
draw element pixels = do
  ctx <- getContext2D (unsafeCoerce element :: CanvasElement)
  putImageData ctx pixels 0.0 0.0

-- | The canvas's `drawImage` takes an `ImageBitmap` too, not only the
-- | image sources the canvas package knows.
asImageSource :: ImageBitmap -> CanvasImageSource
asImageSource = unsafeCoerce
