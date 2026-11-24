-- | Loading a picture in the browser: the browser decodes the file, and
-- | its pixels are read back. It decodes without color conversion, so the
-- | stored values are the ones dithered, as in the CLI (decision 9 in
-- | web/ROADMAP.md). The pixels are read with their transparency, exactly
-- | (decision 27): a 2D canvas gives an opaque picture's values exactly,
-- | but keeps colors premultiplied by alpha, which rounds semi-transparent
-- | ones, so a picture with transparency is read again, as an `<img>`
-- | through WebGL (see `Picture.js` for why not the decoded bitmap).
module Puregrain.Web.Picture
  ( Picture
  , load
  , draw
  , sampleName
  , fetchSample
  , named
  , readClipboard
  ) where

import Prelude

import Control.Promise (Promise, toAffE)
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Either (Either(..))
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Aff (Aff, attempt)
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
-- | WebGL or when the WebGL read didn't agree with the canvas's, which
-- | rounds its semi-transparent colors.
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
foreign import data ImageElement :: Type

foreign import decodeImageImpl :: File -> Effect (Promise ImageElement)

foreign import fetchFileImpl :: String -> String -> Effect (Promise File)

foreign import exactRgbaImpl
  :: (Uint8ClampedArray -> Maybe Uint8ClampedArray)
  -> Maybe Uint8ClampedArray
  -> ImageElement
  -> Int
  -> Int
  -> Uint8ClampedArray
  -> Effect (Maybe Uint8ClampedArray)

-- | Decodes the file and reads its pixels. Fails, in `Aff`, when the
-- | browser can't decode the file as a picture.
load :: File -> Aff Picture
load file = do
  bitmap <- toAffE (decodeImpl file)
  read <- liftEffect do
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
    closeBitmap bitmap
    pure { width, height, fromCanvas, transparent }
  -- With transparency, the picture again as an <img>, through WebGL; the
  -- canvas's bytes if that fails or doesn't agree with them.
  exactly <-
    if read.transparent then do
      decoded <- attempt (toAffE (decodeImageImpl file))
      case decoded of
        Right image -> liftEffect (exactRgbaImpl Just Nothing image read.width read.height read.fromCanvas)
        Left _ -> pure Nothing
    else pure Nothing
  pure case exactly of
    Just pixels -> { name: File.name file, width: read.width, height: read.height, pixels, transparent: read.transparent, exact: true }
    Nothing -> { name: File.name file, width: read.width, height: read.height, pixels: read.fromCanvas, transparent: read.transparent, exact: not read.transparent }

-- | The sample picture's file name (decision 35): the page offers it
-- | before the first picture. `web/build.mjs` copies it from the
-- | repository's `pictures/` into `pictures/` next to the page.
sampleName :: String
sampleName = "macaw-and-toucan.png"

-- | Fetches the sample picture from the page's own site, as a file named
-- | `sampleName`, to load like a chosen one. Fails, in `Aff`, when it
-- | can't be fetched.
fetchSample :: Aff File
fetchSample = toAffE (fetchFileImpl ("pictures/" <> sampleName) sampleName)

foreign import namedImpl :: String -> File -> File

-- | The same file under another name (a pasted picture's, v2.6).
named :: String -> File -> File
named = namedImpl

foreign import readClipboardImpl :: (forall a. a -> Maybe a) -> (forall a. Maybe a) -> Effect (Promise (Maybe File))

-- | The first picture on the clipboard, as a file named `image.png`, as
-- | the paste event names one, or nothing when the clipboard holds none
-- | (v2.6, "paste"). The browser asks first: Chrome for its permission,
-- | Firefox and Safari with a "Paste" button of their own. Fails, in
-- | `Aff`, when it doesn't let the page read the clipboard.
readClipboard :: Aff (Maybe File)
readClipboard = toAffE (readClipboardImpl Just Nothing)

-- | Puts the pixels onto a canvas element of their size.
draw :: HTMLElement -> ImageData -> Effect Unit
draw element pixels = do
  ctx <- getContext2D (unsafeCoerce element :: CanvasElement)
  putImageData ctx pixels 0.0 0.0

-- | The canvas's `drawImage` takes an `ImageBitmap` too, not only the
-- | image sources the canvas package knows.
asImageSource :: ImageBitmap -> CanvasImageSource
asImageSource = unsafeCoerce
