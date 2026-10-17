module Test.Main where

import Prelude

import Effect (Effect)
import Test.Spec.Discovery (discoverAndRunSpecs)
import Test.Spec.Reporter.Console (consoleReporter)

-- | Runs every library spec module: `Test.Puregrain.<Name>Spec`. The
-- | workspace shares one `output/` folder, which also holds the CLI's
-- | specs (`Test.Puregrain.Cli.<Name>Spec`); the anchors and the single
-- | name segment keep those out — the CLI runs them itself. Digits are
-- | allowed in the name, for specs like `C64Spec`.
main :: Effect Unit
main = discoverAndRunSpecs [ consoleReporter ] """^Test\.Puregrain\.[A-Za-z0-9]+Spec$"""
