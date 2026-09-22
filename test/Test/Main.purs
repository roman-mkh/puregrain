module Test.Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)

import Test.Dither.Step as StepTest
import Test.Dither.Row as RowTest
import Test.Dither.Image as ImageTest
import Test.Spec.Discovery (discoverAndRunSpecs)
import Test.Spec.Reporter.Console (consoleReporter)

main :: Effect Unit
main = do
  -- log "Running Dither tests..."
  -- StepTest.main
  -- RowTest.main
  -- ImageTest.main
  discoverAndRunSpecs [consoleReporter] """Dither\..*Spec"""