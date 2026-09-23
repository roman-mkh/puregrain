module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)

import Test.Dither.Image as ImageTest
import Test.Spec.Discovery (discoverAndRunSpecs)
import Test.Spec.Reporter.Console (consoleReporter)

main :: Effect Unit
main = do
  -- log "Running Dither tests..."
  -- ImageTest.main
  discoverAndRunSpecs [consoleReporter] """Dither\..*Spec"""