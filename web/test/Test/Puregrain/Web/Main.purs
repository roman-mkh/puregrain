module Test.Puregrain.Web.Main where

import Prelude

import Effect (Effect)
import Test.Puregrain.Web.ZoomSpec as ZoomSpec
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)

-- An explicit list rather than spec-discovery, as for the CLI's specs:
-- the workspace shares one `output/` folder.
main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] do
  ZoomSpec.spec
