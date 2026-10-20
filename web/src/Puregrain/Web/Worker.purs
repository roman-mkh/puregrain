-- | The web UI's worker: it runs apart from the page, so long work doesn't
-- | freeze the page. Bundled as `worker.js` (see web/build.mjs) and started
-- | by the page as a classic worker. For now (phase 1 of web/ROADMAP.md)
-- | it answers each message with the same data.
module Puregrain.Web.Worker (main) where

import Prelude

import Effect (Effect)
import Web.Worker.DedicatedWorkerGlobalScope as Self
import Web.Worker.MessageEvent (data_)
import Web.Worker.Types (unsafeWrap)

main :: Effect Unit
main = Self.onMessage \event -> Self.postMessage (unsafeWrap (data_ event))
