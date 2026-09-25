module Test.Puregrain.Cli.Main where

import Prelude

import Effect (Effect)
import Test.Puregrain.Cli.OptionsSpec as OptionsSpec
import Test.Puregrain.Cli.PipelineSpec as PipelineSpec
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)

-- An explicit list rather than spec-discovery: the workspace shares one
-- `output/` folder, and two packages each scanning it by regex is more
-- fragile than naming two modules.
main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] do
  OptionsSpec.spec
  PipelineSpec.spec
