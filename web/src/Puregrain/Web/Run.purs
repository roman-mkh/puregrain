-- | Dithering a picture's pixels with the settings: what the worker runs.
-- | Apart from the worker's messaging, so specs can run it in Node.
module Puregrain.Web.Run (ditherPicture) where

import Prelude

import Data.Array as Array
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), isNothing)
import Effect (Effect)
import Effect.Ref as Ref
import Puregrain (class Scalable, Dithering, ditherRow, initDithering)
import Puregrain.Web.Dither (Pipeline(..), kernelOf, luma, pipelineFor, toNeutral)
import Puregrain.Web.Pixels (allNeutral, newPixels, readRow, writeGrayRow, writeRgbRow)
import Puregrain.Web.Settings (Settings)

-- | Dithers the picture (RGBA bytes, `width` × `height`) with the
-- | settings, row by row with the library's stepper, as the CLI dithers it:
-- | gray processing for an all-neutral picture or when the settings turn
-- | it gray, and each channel rounded and clamped as the CLI writes PNGs.
-- | `progress` is called after every hundredth of the rows and after the
-- | last. The result's pixels, or why there are none.
ditherPicture
  :: Settings
  -> { width :: Int, height :: Int, pixels :: Uint8ClampedArray }
  -> ({ done :: Int, total :: Int } -> Effect Unit)
  -> Effect (Either String Uint8ClampedArray)
ditherPicture settings picture progress = do
  grayPicture <- if settings.gray then pure true else allNeutral picture.pixels
  case pipelineFor settings grayPicture of
    Nothing -> pure (Left "nothing to dither: the colors are none")
    Just pipeline -> do
      out <- newPixels (picture.width * picture.height * 4)
      let
        kernel = kernelOf settings.kernel
        rgbRow y = (if settings.gray then map toNeutral else identity) <$> readRow picture.pixels picture.width y
      failure <- case pipeline of
        Gray q -> ditherRows picture.height (initDithering kernel q) (map (map luma) <<< rgbRow) (writeGrayRow out picture.width) progress
        Color q -> ditherRows picture.height (initDithering kernel q) rgbRow (writeRgbRow out picture.width) progress
      pure case failure of
        Just message -> Left message
        Nothing -> Right out

-- | The rows one by one through the stepper: each read with `read` and
-- | its result written with `write`. A row the stepper refuses (one of
-- | another length, which can't happen here) stops it with the message.
ditherRows
  :: forall a
   . Ring a
  => Scalable a
  => Int
  -> Dithering a
  -> (Int -> Effect (Array a))
  -> (Int -> Array a -> Effect Unit)
  -> ({ done :: Int, total :: Int } -> Effect Unit)
  -> Effect (Maybe String)
ditherRows height start read write progress = do
  state <- Ref.new start
  failure <- Ref.new Nothing
  let every = max 1 (height / 100)
  for_ (if height > 0 then Array.range 0 (height - 1) else []) \y -> do
    stopped <- Ref.read failure
    when (isNothing stopped) do
      d <- Ref.read state
      row <- read y
      case ditherRow d row of
        Left message -> Ref.write (Just message) failure
        Right r -> do
          write y r.row
          Ref.write r.next state
          when ((y + 1) `mod` every == 0 || y + 1 == height) (progress { done: y + 1, total: height })
  Ref.read failure
