-- | The web UI's worker: it runs apart from the page, so dithering doesn't
-- | freeze the page. Bundled as `worker.js` (see web/build.mjs) and
-- | started by the page as a classic worker, one per run: cancelling ends
-- | it (decision 11 in web/ROADMAP.md).
-- |
-- | It reads its job, dithers the picture (`Puregrain.Web.Run`), reports
-- | the progress, and sends the result's pixels and a machine's files,
-- | transferred, not copied. Or, in a worker of its own started once when
-- | the page loads, it runs the library's engine check
-- | (`Puregrain.SelfCheck`) and says whether it passed.
module Puregrain.Web.Worker (main) where

import Prelude

import Control.Monad.Except (runExcept)
import Data.Either (Either(..))
import Effect (Effect)
import Puregrain.SelfCheck (checkEngine, exactArithmetic, problems)
import Puregrain.Web.Message (Request(..), describe, doneMessage, engineMessage, errorMessage, progressMessage, readRequest)
import Puregrain.Web.Pixels (transferable)
import Puregrain.Web.Run (ditherPicture)
import Web.Worker.DedicatedWorkerGlobalScope as Self
import Web.Worker.MessageEvent (data_)

main :: Effect Unit
main = Self.onMessage \event -> case runExcept (readRequest (data_ event)) of
  Left errors -> Self.postMessage (errorMessage ("the worker couldn't read its job: " <> describe errors))
  Right CheckEngine -> do
    report <- checkEngine
    Self.postMessage (engineMessage { passed: exactArithmetic report, problems: problems report })
  Right (DitherJob job) -> do
    result <- ditherPicture job (Self.postMessage <<< progressMessage)
    case result of
      Left reason -> Self.postMessage (errorMessage reason)
      Right out -> Self.postMessage' (doneMessage out) ([ transferable out.pixels ] <> map (transferable <<< _.bytes) out.files)
