-- | The puregrain command-line tool: dithers a PNG with the library's
-- | top-level `ditherImage`. Run it through `npm run dither-cli -- ...`
-- | (the launcher in cli/bin runs the compiled output directly).
module Puregrain.Cli.Main (main) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.List.Lazy as LL
import Data.Maybe (maybe)
import Data.Number.Format (fixed, toStringWith)
import Data.Tuple (Tuple(..))
import Dither.Image (ditherImage)
import Dither.Kernel (Kernel)
import Dither.Pixel (class Scalable, Quantize, RGB(..))
import Effect (Effect)
import Effect.Console (error, log)
import Effect.Exception (message, try)
import Node.Process (exit')
import Options.Applicative (execParser)
import Puregrain.Cli.Options (Options, describeQuantizer, kernelName, parserInfo)
import Puregrain.Cli.Pipeline (Pipeline(..), isNeutral, kernelOf, luma, pipelineFor, toNeutral)
import Puregrain.Cli.Png (nowMs, readRgbRows, writeGrayRows, writeRgbRows)
import Safe.Coerce (coerce)

main :: Effect Unit
main = do
  opts <- execParser parserInfo
  result <- try (run opts)
  case result of
    Left err -> do
      error (message err)
      exit' 1
    Right _ -> pure unit

-- | The library's top-level `ditherImage`, on an in-memory image. The
-- | result list is lazy; `LL.toUnfoldable` forces all of it.
dither :: forall a. Ring a => Scalable a => Kernel -> Quantize a -> Array (Array a) -> Array (Array a)
dither kernel quantize rows = LL.toUnfoldable (ditherImage kernel quantize (LL.fromFoldable rows))

-- | Evaluates `f unit` between two clock reads and returns the elapsed
-- | milliseconds with the result. PureScript is strict and `dither`
-- | forces the whole lazy image, so this measures exactly the dithering —
-- | not PNG decoding/encoding, gray conversion, or process startup.
timed :: forall a. (Unit -> a) -> Effect (Tuple Number a)
timed f = do
  t0 <- nowMs
  let result = f unit
  t1 <- nowMs
  pure (Tuple (t1 - t0) result)

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
      let grayRows = map (map luma) image
      Tuple ms out <- timed \_ -> dither kernel q grayRows
      report ms "gray"
      writeGrayRows opts.output out
      log $ "Wrote " <> opts.output <> " (grayscale PNG)"
    Color q -> do
      Tuple ms out <- timed \_ -> dither kernel q image
      report ms "RGB"
      writeRgbRows opts.output (coerce out)
      log $ "Wrote " <> opts.output <> " (RGB PNG)"
  where
  report ms space = log $ "Dithered in " <> toStringWith (fixed 1) ms <> " ms ("
    <> kernelName opts.kernel <> ", " <> describeQuantizer opts.quantizer <> ", " <> space <> ")"
