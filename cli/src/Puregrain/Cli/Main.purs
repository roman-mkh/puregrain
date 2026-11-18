-- | The puregrain command-line tool: dithers a PNG with the library's
-- | `ditherImage`, or with `ditherCells` for a machine's screen, written
-- | as a PNG or as the machine's own screen file. Run it through
-- | `npm run dither-cli -- ...` (the launcher in cli/bin runs the compiled
-- | output directly).
module Puregrain.Cli.Main (main) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..), either)
import Data.Enum (fromEnum)
import Data.Maybe (Maybe(..), maybe)
import Data.Number.Format (fixed, toStringWith)
import Data.String (joinWith)
import Data.Tuple (Tuple(..))
import Puregrain (RGB(..), ditherImageWith, toGray)
import Effect (Effect)
import Effect.Console (error, log)
import Effect.Exception (catchException, message, throw, try)
import ExitCodes as ExitCode
import Node.Buffer as Buffer
import Node.FS.Sync (writeFile)
import Node.Process (argv, exit', setExitCode)
import Options.Applicative (ParserResult(..), handleParseResult, renderFailure)
import Puregrain.Cli.Options (Command(..), FormatName(..), GammaName(..), Options, describeQuantizer, gammaName, kernelName, parseOptions, programName)
import Puregrain.Cli.Pipeline (Pipeline(..), artStudioFile, ditherScreen, gammaOf, isNeutral, kernelOf, pipelineFor, programFile, screenFile, screenImage, screenSizeCheck, tapeFile, tapeName, toNeutral)
import Puregrain.Cli.Png (readRgbRows, writeGrayRows, writeRgbRows)
import Puregrain.Cli.Timing (timed)
-- A specialty module, outside the facade, imported directly as an
-- application would.
import Puregrain.SelfCheck (checkEngine, exactArithmetic, problems)
import Safe.Coerce (coerce)

main :: Effect Unit
main = do
  args <- argv
  command <- answered (parseOptions (Array.drop 2 args))
  case command of
    Nothing -> pure unit
    Just CheckEngine -> checkTheEngine
    Just (Dither opts) -> do
      result <- try (run opts)
      case result of
        Left err -> do
          error (message err)
          exit' 1
        Right _ -> pure unit

-- | What optparse answers itself (the help, `--version`, a rejected
-- | command line), printed under the command's own name, `programName`,
-- | not the script's file name: optparse's `handleParseResult` with the
-- | name fixed. It sets the exit code and returns instead of exiting at
-- | once, so the text is written out in full even through a pipe. Shell
-- | completion keeps optparse's own handling.
answered :: ParserResult Command -> Effect (Maybe Command)
answered = case _ of
  Success command -> pure (Just command)
  Failure failure -> do
    let Tuple text code = renderFailure failure programName
    if code == ExitCode.Success then log text else error text
    setExitCode (fromEnum code)
    pure Nothing
  completion -> Just <$> handleParseResult completion

-- | `--check-engine`: runs the library's self-check, says what it found,
-- | and exits with 1 on a problem.
checkTheEngine :: Effect Unit
checkTheEngine = do
  report <- checkEngine
  if exactArithmetic report then
    log "Engine check passed: this JavaScript engine computes the light curves exactly as the reference does."
  else do
    error (joinWith "\n  " ([ "Engine check failed:" ] <> problems report))
    exit' 1

run :: Options -> Effect Unit
run opts = do
  rows <- readRgbRows opts.input
  let
    gamma = gammaOf opts.gamma
    image :: Array (Array RGB)
    image = (if opts.gray then map (map (toNeutral gamma)) else identity) (coerce rows)
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
      { ms, result: out } <- timed (ditherImageWith gamma kernel q) (map (map (toGray gamma)) image)
      report ms "gray"
      writeGrayRows opts.output out
      log $ "Wrote " <> opts.output <> " (grayscale PNG)"
    Color q -> do
      { ms, result: out } <- timed (ditherImageWith gamma kernel q) image
      report ms "RGB"
      writeRgbRows opts.output (coerce out)
      log $ "Wrote " <> opts.output <> " (RGB PNG)"
    Screen { machine, palette, rule } -> do
      note <- either throw pure (screenSizeCheck opts.format machine width (Array.length image))
      maybe (pure unit) log note
      { ms, result: out } <- timed (ditherScreen gamma machine palette kernel rule) image
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
        Prg -> do
          bytes <- either throw pure (programFile out)
          writeBytes opts.output bytes
          log $ "Wrote " <> opts.output <> " (C64 program, " <> show (Array.length bytes) <> " bytes)"
        Art -> do
          bytes <- either throw pure (artStudioFile out)
          writeBytes opts.output bytes
          log $ "Wrote " <> opts.output <> " (Art Studio picture, " <> show (Array.length bytes) <> " bytes)"
  where
  report ms space = log $ "Dithered in " <> toStringWith (fixed 1) ms <> " ms ("
    <> kernelName opts.kernel <> ", " <> describeQuantizer opts.quantizer <> gammaPart <> ", " <> space <> ")"
  -- Named only when it isn't off, so that the line stays as it was.
  gammaPart = if opts.gamma == GammaOff then "" else ", gamma " <> gammaName opts.gamma

-- | Writes bytes to a file. An error names the file, as the PNG writer's
-- | do.
writeBytes :: String -> Array Int -> Effect Unit
writeBytes path bytes = catchException failed (Buffer.fromArray bytes >>= writeFile path)
  where
  failed err = throw ("Cannot write \"" <> path <> "\": " <> message err)
