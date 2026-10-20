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
-- | - The page sends a job: the settings, the picture's size, and a copy
-- |   of its pixels (transferred).
-- | - The worker answers with progress after every few rows, then the
-- |   result's pixels (transferred), or an error.
module Puregrain.Web.Message
  ( Job
  , JobMessage
  , jobMessage
  , readJob
  , Reply(..)
  , progressMessage
  , doneMessage
  , errorMessage
  , readReply
  , describe
  ) where

import Prelude

import Control.Monad.Except (Except)
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Foldable (intercalate)
import Data.List.NonEmpty (NonEmptyList)
import Data.Maybe (maybe)
import Foreign (Foreign, ForeignError(..), fail, readBoolean, readInt, readString, renderForeignError, tagOf, unsafeFromForeign)
import Foreign.Index (readProp)
import Puregrain.Web.Settings (Settings, SettingsMessage, fromMessage, toMessage)
import Web.Worker.Types (SendWrapper, unsafeWrap)

type Job = { settings :: Settings, width :: Int, height :: Int, pixels :: Uint8ClampedArray }

type JobMessage = { settings :: SettingsMessage, width :: Int, height :: Int, pixels :: Uint8ClampedArray }

jobMessage :: Job -> SendWrapper JobMessage
jobMessage job = unsafeWrap (job { settings = toMessage job.settings })

readJob :: Foreign -> Except (NonEmptyList ForeignError) Job
readJob message = do
  s <- readProp "settings" message
  settingsMessage <- { colors: _, amount: _, kernel: _, bayer: _, gray: _ }
    <$> (readProp "colors" s >>= readString)
    <*> (readProp "amount" s >>= readInt)
    <*> (readProp "kernel" s >>= readString)
    <*> (readProp "bayer" s >>= readInt)
    <*> (readProp "gray" s >>= readBoolean)
  settings <- maybe (fail (ForeignError ("settings the page wouldn't send: " <> show settingsMessage))) pure (fromMessage settingsMessage)
  width <- readProp "width" message >>= readInt
  height <- readProp "height" message >>= readInt
  pixels <- readProp "pixels" message >>= readPixels
  pure { settings, width, height, pixels }

-- | What the worker answers: progress, in rows done of all, the result's
-- | pixels, or an error.
data Reply
  = Progress { done :: Int, total :: Int }
  | Done Uint8ClampedArray
  | Failure String

progressMessage :: { done :: Int, total :: Int } -> SendWrapper { kind :: String, done :: Int, total :: Int }
progressMessage p = unsafeWrap { kind: "progress", done: p.done, total: p.total }

doneMessage :: Uint8ClampedArray -> SendWrapper { kind :: String, pixels :: Uint8ClampedArray }
doneMessage pixels = unsafeWrap { kind: "done", pixels }

errorMessage :: String -> SendWrapper { kind :: String, message :: String }
errorMessage message = unsafeWrap { kind: "error", message }

readReply :: Foreign -> Except (NonEmptyList ForeignError) Reply
readReply message = do
  kind <- readProp "kind" message >>= readString
  case kind of
    "progress" -> do
      done <- readProp "done" message >>= readInt
      total <- readProp "total" message >>= readInt
      pure (Progress { done, total })
    "done" -> Done <$> (readProp "pixels" message >>= readPixels)
    "error" -> Failure <$> (readProp "message" message >>= readString)
    _ -> fail (ForeignError ("an unknown kind of reply: " <> kind))

readPixels :: Foreign -> Except (NonEmptyList ForeignError) Uint8ClampedArray
readPixels value =
  if tagOf value == "Uint8ClampedArray" then pure (unsafeFromForeign value)
  else fail (TypeMismatch "Uint8ClampedArray" (tagOf value))

-- | Decoding errors as one line, for an error message.
describe :: NonEmptyList ForeignError -> String
describe = intercalate "; " <<< map renderForeignError
