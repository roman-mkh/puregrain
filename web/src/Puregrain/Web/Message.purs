-- | The messages between the page and the worker, and how each side reads
-- | the other's. They arrive as `Foreign` values and are decoded, not
-- | trusted: a message that doesn't fit becomes an error.
-- |
-- | Each message is sent wrapped with `unsafeWrap`: `web-workers` 2.0.0's
-- | instance for sending a record needs a class it doesn't export
-- | (`IsSendableRowList`), so no record passes its check. The records
-- | here hold only plain data and typed arrays, which a browser copies or
-- | transfers between threads; the receiving side checks them.
-- |
-- | - The page sends a job: the settings, the picture's size, a copy of
-- |   its pixels (transferred), and the name for a ZX Spectrum tape.
-- | - The worker answers with progress after every few rows, then the
-- |   result's pixels and, for a machine's screen, its files (all
-- |   transferred), or an error.
-- | - Or the page asks for the engine check (`checkMessage`), and the
-- |   worker answers whether it passed, with the problems found.
module Puregrain.Web.Message
  ( Job
  , FileBytes
  , JobMessage
  , jobMessage
  , readJob
  , checkMessage
  , Request(..)
  , readRequest
  , Reply(..)
  , progressMessage
  , doneMessage
  , errorMessage
  , engineMessage
  , readReply
  , describe
  ) where

import Prelude

import Control.Monad.Except (Except)
import Data.ArrayBuffer.Types (Uint8Array, Uint8ClampedArray)
import Data.Foldable (intercalate)
import Data.List.NonEmpty (NonEmptyList)
import Data.Maybe (maybe)
import Data.Traversable (traverse)
import Foreign (Foreign, ForeignError(..), fail, isUndefined, readArray, readBoolean, readInt, readString, renderForeignError, tagOf, unsafeFromForeign)
import Foreign.Index (readProp)
import Puregrain.Web.Settings (Settings, SettingsMessage, fromMessage, toMessage)
import Web.Worker.Types (SendWrapper, unsafeWrap)

-- | What to dither: the settings, the picture (RGBA bytes, `width` ×
-- | `height`), and the name for a ZX Spectrum tape.
type Job = { settings :: Settings, width :: Int, height :: Int, pixels :: Uint8ClampedArray, tapeName :: String }

-- | One of a machine's files, by its format's name (`scr`, `tap`, `prg`,
-- | `art`, as the CLI's `--format`).
type FileBytes = { format :: String, bytes :: Uint8Array }

type JobMessage = { settings :: SettingsMessage, width :: Int, height :: Int, pixels :: Uint8ClampedArray, tapeName :: String }

jobMessage :: Job -> SendWrapper JobMessage
jobMessage job = unsafeWrap (job { settings = toMessage job.settings })

readJob :: Foreign -> Except (NonEmptyList ForeignError) Job
readJob message = do
  s <- readProp "settings" message
  settingsMessage <- { target: _, colors: _, amount: _, kernel: _, bayer: _, gray: _, gamma: _ }
    <$> (readProp "target" s >>= readString)
    <*> (readProp "colors" s >>= readString)
    <*> (readProp "amount" s >>= readInt)
    <*> (readProp "kernel" s >>= readString)
    <*> (readProp "bayer" s >>= readInt)
    <*> (readProp "gray" s >>= readBoolean)
    <*> (readProp "gamma" s >>= readString)
  settings <- maybe (fail (ForeignError ("settings the page wouldn't send: " <> show settingsMessage))) pure (fromMessage settingsMessage)
  width <- readProp "width" message >>= readInt
  height <- readProp "height" message >>= readInt
  pixels <- readProp "pixels" message >>= readPixels
  tapeName <- readProp "tapeName" message >>= readString
  pure { settings, width, height, pixels, tapeName }

-- | The page's request for the engine check, which a worker of its own
-- | runs once, when the page has loaded (linear light, step 4c). A job
-- | has no `kind`.
checkMessage :: SendWrapper { kind :: String }
checkMessage = unsafeWrap { kind: "check" }

-- | What a worker is asked: a picture to dither, or the engine check.
data Request = DitherJob Job | CheckEngine

-- | A message to the worker: the engine check by its `kind`, a job
-- | without one.
readRequest :: Foreign -> Except (NonEmptyList ForeignError) Request
readRequest message = do
  kind <- readProp "kind" message
  if isUndefined kind then DitherJob <$> readJob message
  else do
    name <- readString kind
    if name == "check" then pure CheckEngine
    else fail (ForeignError ("an unknown kind of request: " <> name))

-- | What the worker answers: progress, in rows done of all, the result's
-- | pixels with a machine's files, or an error; for the engine check,
-- | whether it passed, and the problems found.
data Reply
  = Progress { done :: Int, total :: Int }
  | Done { pixels :: Uint8ClampedArray, files :: Array FileBytes }
  | Failure String
  | Engine { passed :: Boolean, problems :: Array String }

progressMessage :: { done :: Int, total :: Int } -> SendWrapper { kind :: String, done :: Int, total :: Int }
progressMessage p = unsafeWrap { kind: "progress", done: p.done, total: p.total }

doneMessage :: { pixels :: Uint8ClampedArray, files :: Array FileBytes } -> SendWrapper { kind :: String, pixels :: Uint8ClampedArray, files :: Array FileBytes }
doneMessage result = unsafeWrap { kind: "done", pixels: result.pixels, files: result.files }

errorMessage :: String -> SendWrapper { kind :: String, message :: String }
errorMessage message = unsafeWrap { kind: "error", message }

engineMessage :: { passed :: Boolean, problems :: Array String } -> SendWrapper { kind :: String, passed :: Boolean, problems :: Array String }
engineMessage result = unsafeWrap { kind: "engine", passed: result.passed, problems: result.problems }

readReply :: Foreign -> Except (NonEmptyList ForeignError) Reply
readReply message = do
  kind <- readProp "kind" message >>= readString
  case kind of
    "progress" -> do
      done <- readProp "done" message >>= readInt
      total <- readProp "total" message >>= readInt
      pure (Progress { done, total })
    "done" -> do
      pixels <- readProp "pixels" message >>= readPixels
      files <- readProp "files" message >>= readArray >>= traverse readFileBytes
      pure (Done { pixels, files })
    "error" -> Failure <$> (readProp "message" message >>= readString)
    "engine" -> do
      passed <- readProp "passed" message >>= readBoolean
      problems <- readProp "problems" message >>= readArray >>= traverse readString
      pure (Engine { passed, problems })
    _ -> fail (ForeignError ("an unknown kind of reply: " <> kind))

readPixels :: Foreign -> Except (NonEmptyList ForeignError) Uint8ClampedArray
readPixels value =
  if tagOf value == "Uint8ClampedArray" then pure (unsafeFromForeign value)
  else fail (TypeMismatch "Uint8ClampedArray" (tagOf value))

readFileBytes :: Foreign -> Except (NonEmptyList ForeignError) FileBytes
readFileBytes value = do
  format <- readProp "format" value >>= readString
  bytes <- readProp "bytes" value
  if tagOf bytes == "Uint8Array" then pure { format, bytes: unsafeFromForeign bytes }
  else fail (TypeMismatch "Uint8Array" (tagOf bytes))

-- | Decoding errors as one line, for an error message.
describe :: NonEmptyList ForeignError -> String
describe = intercalate "; " <<< map renderForeignError
