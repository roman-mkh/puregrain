-- | The puregrain command-line tool: dithers a PNG with the library's
-- | `ditherImage`, or with `ditherCells` for a machine's screen, written
-- | as a PNG or as the machine's own screen file. Run it through
-- | `npm run dither-cli -- ...` (the launcher in cli/bin runs the compiled
-- | output directly).
module Puregrain.Cli.Main (main) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..), either)
import Data.Maybe (maybe)
import Data.Number.Format (fixed, toStringWith)
import Puregrain (RGB(..), ditherImage)
import Effect (Effect)
import Effect.Console (error, log)
import Effect.Exception (catchException, message, throw, try)
import Node.Buffer as Buffer
import Node.FS.Sync (writeFile)
import Node.Process (argv, exit')
import Options.Applicative (handleParseResult)
import Puregrain.Cli.Options (FormatName(..), Options, describeQuantizer, kernelName, parseOptions)
import Puregrain.Cli.Pipeline (Pipeline(..), ditherScreen, isNeutral, kernelOf, luma, pipelineFor, screenFile, screenImage, screenSizeCheck, tapeFile, tapeName, toNeutral)
import Puregrain.Cli.Png (readRgbRows, writeGrayRows, writeRgbRows)
import Puregrain.Cli.Timing (timed)
import Safe.Coerce (coerce)

main :: Effect Unit
main = do
  args <- argv
  opts <- handleParseResult (parseOptions (Array.drop 2 args))
  result <- try (run opts)
  case result of
    Left err -> do
      error (message err)
      exit' 1
    Right _ -> pure unit

run :: Options -> Effect Unit
run opts = do
  rows <- readRgbRows opts.input
  let
    image :: Array (Array RGB)
    image = (if opts.gray then map (map toNeutral) else identity) (coerce rows)
    grayImage = Array.all (Array.all isNeutral) image
    kernel = kernelOf opts.kernel
    width = maybe 0 Array.length (Array.head image)
  log $ "Read " <> opts.input <> ": " <> show width <> "x" <> show (Array.length image)
    <> (if grayImage then ", gray" else ", color")
  case pipelineFor opts.quantizer grayImage of
    Gray q -> do
      -- `timed` gets the input separately, so the gray conversion is done
      -- before the clock starts: only the dithering is measured (see
      -- Puregrain.Cli.Timing).
      { ms, result: out } <- timed (ditherImage kernel q) (map (map luma) image)
      report ms "gray"
      writeGrayRows opts.output out
      log $ "Wrote " <> opts.output <> " (grayscale PNG)"
    Color q -> do
      { ms, result: out } <- timed (ditherImage kernel q) image
      report ms "RGB"
      writeRgbRows opts.output (coerce out)
      log $ "Wrote " <> opts.output <> " (RGB PNG)"
    Screen { machine, palette, rule } -> do
      note <- either throw pure (screenSizeCheck opts.format machine width (Array.length image))
      maybe (pure unit) log note
      { ms, result: out } <- timed (ditherScreen machine palette kernel rule) image
      report ms "RGB"
      case opts.format of
        Png -> do
          writeRgbRows opts.output (coerce (screenImage out))
          log $ "Wrote " <> opts.output <> " (RGB PNG)"
        Scr -> do
          bytes <- either throw pure (screenFile out)
          writeBytes opts.output bytes
          log $ "Wrote " <> opts.output <> " (ZX Spectrum screen, " <> show (Array.length bytes) <> " bytes)"
        Tap -> do
          bytes <- either throw pure (tapeFile (tapeName opts.output) out)
          writeBytes opts.output bytes
          log $ "Wrote " <> opts.output <> " (ZX Spectrum tape, " <> show (Array.length bytes) <> " bytes)"
  where
  report ms space = log $ "Dithered in " <> toStringWith (fixed 1) ms <> " ms ("
    <> kernelName opts.kernel <> ", " <> describeQuantizer opts.quantizer <> ", " <> space <> ")"

-- | Writes bytes to a file. An error names the file, as the PNG writer's
-- | do.
writeBytes :: String -> Array Int -> Effect Unit
writeBytes path bytes = catchException failed (Buffer.fromArray bytes >>= writeFile path)
  where
  failed err = throw ("Cannot write \"" <> path <> "\": " <> message err)
