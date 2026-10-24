-- | Dithering a picture's pixels with the settings: what the worker runs.
-- | Apart from the worker's messaging, so specs can run it in Node.
module Puregrain.Web.Run
  ( Result
  , ditherPicture
  ) where

import Prelude

import Data.Array as Array
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Either (Either(..))
import Data.Foldable (for_)
import Data.FoldableWithIndex (forWithIndex_)
import Data.List (List(..))
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..), isNothing)
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..))
import Data.Unfoldable (unfoldr)
import Effect (Effect, untilE)
import Effect.Ref as Ref
import Puregrain (class Scalable, Dithering, RGB, ditherRow, initDithering)
import Puregrain.Cells (CellMode, ditherBands)
import Puregrain.Machine.C64 as C64
import Puregrain.Machine.ZxSpectrum as Zx
import Puregrain.Web.Dither (Pipeline(..), kernelOf, luma, pipelineFor, toNeutral, zxModeOf)
import Puregrain.Web.Message (FileBytes, Job)
import Puregrain.Web.Pixels (allNeutral, bytesOf, newPixels, readRow, rowAt, writeGrayRow, writeRgbRow)
import Puregrain.Web.Settings (MachineName(..), screenSizeOf)

-- | The result's pixels, and for a machine's screen of the screen's size
-- | the machine's files.
type Result = { pixels :: Uint8ClampedArray, files :: Array FileBytes }

-- | Dithers the picture with the settings, as the CLI dithers it. Plain
-- | dithering goes row by row with the library's stepper: gray processing
-- | for an all-neutral picture or when the settings turn it gray, each
-- | channel rounded and clamped as the CLI writes PNGs; `progress` after
-- | every hundredth of the rows and after the last. A machine's screen
-- | goes band by band, a row of cells at a time, with `progress` after
-- | each band; at the screen's size its files come with it. The result,
-- | or why there's none.
ditherPicture :: Job -> ({ done :: Int, total :: Int } -> Effect Unit) -> Effect (Either String Result)
ditherPicture job progress = do
  grayPicture <- if job.settings.gray then pure true else allNeutral job.pixels
  case pipelineFor job.settings grayPicture of
    Nothing -> pure (Left "nothing to dither: the colors are none")
    Just pipeline -> do
      out <- newPixels (job.width * job.height * 4)
      let
        kernel = kernelOf job.settings.kernel
        gray = if job.settings.gray then map toNeutral else identity
        rgbRow y = gray <$> readRow job.pixels job.width y
      case pipeline of
        Gray q -> plain out =<< ditherRows job.height (initDithering kernel q) (map (map luma) <<< rgbRow) (writeGrayRow out job.width) progress
        Color q -> plain out =<< ditherRows job.height (initDithering kernel q) rgbRow (writeRgbRow out job.width) progress
        Screen screen -> do
          let
            -- The rows as the bands need them (the job's pixels don't
            -- change). Made afresh for `bandsInto`, so that no variable
            -- holds the lists' first cells: a lazy list keeps every cell
            -- it has computed, rows and bands, for whatever holds its
            -- start, which would keep a whole poster in memory.
            rowsFrom :: Unit -> LL.List (Array RGB)
            rowsFrom _ = unfoldr (\y -> if y < job.height then Just (Tuple (gray (rowAt job.pixels job.width y)) (y + 1)) else Nothing) 0
            atSize = { width: job.width, height: job.height } == screenSizeOf screen.machine
            bands :: forall c. CellMode c -> Effect { cells :: Array (Array c), image :: Array (Array RGB) }
            bands mode = bandsInto (\_ -> ditherBands kernel screen.rule mode (rowsFrom unit)) out job.width job.height atSize progress
          files <- case screen.machine of
            ZxSpectrumScreen -> do
              dithered <- bands (zxModeOf screen.palette)
              filesOf atSize [ { format: "scr", bytes: Zx.toScr dithered }, { format: "tap", bytes: Zx.toTap job.tapeName dithered } ]
            C64HiresScreen -> do
              dithered <- bands C64.hiresScreen
              filesOf atSize [ { format: "prg", bytes: C64.toHiresPrg dithered }, { format: "art", bytes: C64.toArtStudio dithered } ]
          pure ({ pixels: out, files: _ } <$> files)
  where
  plain out = case _ of
    Just message -> pure (Left message)
    Nothing -> pure (Right { pixels: out, files: [] })

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

-- | The bands one by one, as `ditherBands` gives them (made here, so
-- | only the loop's reference holds them, moving on band by band): each
-- | band's rows written into `out`, `progress` with the rows done so
-- | far, counted from the band (the last one may be partial). The cells
-- | of all the bands, and with `keep` their rows, for a machine's file
-- | writers.
bandsInto
  :: forall c
   . (Unit -> LL.List { cells :: Array c, rows :: Array (Array RGB) })
  -> Uint8ClampedArray
  -> Int
  -> Int
  -> Boolean
  -> ({ done :: Int, total :: Int } -> Effect Unit)
  -> Effect { cells :: Array (Array c), image :: Array (Array RGB) }
bandsInto bandsFrom out width height keep progress = do
  rest <- Ref.new (bandsFrom unit)
  done <- Ref.new 0
  cells <- Ref.new Nil
  image <- Ref.new Nil
  untilE do
    remaining <- Ref.read rest
    case LL.uncons remaining of
      Nothing -> pure true
      Just { head: band, tail } -> do
        d <- Ref.read done
        forWithIndex_ band.rows \i row -> writeRgbRow out width (d + i) row
        Ref.modify_ (Cons band.cells) cells
        when keep (Ref.modify_ (Cons band.rows) image)
        let d' = d + Array.length band.rows
        Ref.write d' done
        Ref.write tail rest
        progress { done: d', total: height }
        pure false
  bandCells <- Ref.read cells
  bandRows <- Ref.read image
  pure { cells: Array.reverse (Array.fromFoldable bandCells), image: Array.concat (Array.reverse (Array.fromFoldable bandRows)) }

-- | A machine's files, at the screen's size, else none; a writer's
-- | refusal (which the size check rules out) as the message.
filesOf :: Boolean -> Array { format :: String, bytes :: Either String (Array Int) } -> Effect (Either String (Array FileBytes))
filesOf atSize files =
  if not atSize then pure (Right [])
  else case traverse (\f -> { format: f.format, bytes: _ } <$> f.bytes) files of
    Left message -> pure (Left message)
    Right made -> Right <$> traverse (\f -> { format: f.format, bytes: _ } <$> bytesOf f.bytes) made
