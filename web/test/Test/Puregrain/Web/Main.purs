module Test.Puregrain.Web.Main where

import Prelude

import Effect (Effect)
import Test.Puregrain.Web.DitherSpec as DitherSpec
import Test.Puregrain.Web.DragSpec as DragSpec
import Test.Puregrain.Web.EstimateSpec as EstimateSpec
import Test.Puregrain.Web.MessageSpec as MessageSpec
import Test.Puregrain.Web.PrepareSpec as PrepareSpec
import Test.Puregrain.Web.RunSpec as RunSpec
import Test.Puregrain.Web.SaveSpec as SaveSpec
import Test.Puregrain.Web.SettingsSpec as SettingsSpec
import Test.Puregrain.Web.SplitSpec as SplitSpec
import Test.Puregrain.Web.StatusSpec as StatusSpec
import Test.Puregrain.Web.ThemeSpec as ThemeSpec
import Test.Puregrain.Web.ZoomSpec as ZoomSpec
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)

-- An explicit list rather than spec-discovery, as for the CLI's specs:
-- the workspace shares one `output/` folder.
main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] do
  SettingsSpec.spec
  DitherSpec.spec
  DragSpec.spec
  EstimateSpec.spec
  MessageSpec.spec
  PrepareSpec.spec
  RunSpec.spec
  SaveSpec.spec
  SplitSpec.spec
  StatusSpec.spec
  ThemeSpec.spec
  ZoomSpec.spec
