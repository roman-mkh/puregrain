module Test.Puregrain.SelfCheckSpec (spec) where

import Prelude

import Data.Array as Array
import Data.String (Pattern(..), contains)
import Effect.Class (liftEffect)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

import Puregrain.Internal.SelfCheck (fingerprint, referenceDigests, reportFor)
import Puregrain.SelfCheck (checkEngine, exactArithmetic, problems)

spec :: Spec Unit
spec = describe "Puregrain.SelfCheck" do

  it "passes on this engine" do
    report <- liftEffect checkEngine
    problems report `shouldEqual` []
    exactArithmetic report `shouldEqual` true

  it "names the curve and direction whose results differ" do
    let
      wrong = Array.mapWithIndex (\i d -> if i == 3 then d { digest = d.digest + 1.0 } else d) referenceDigests
      report = reportFor wrong (fingerprint unit) []
    exactArithmetic report `shouldEqual` false
    Array.length (problems report) `shouldEqual` 1
    problems report `shouldSatisfy` Array.all (contains (Pattern "gamma1p5, back: the results differ"))

  it "passes other problems on, after the digests'" do
    let report = reportFor referenceDigests referenceDigests [ "gammaSrgb: byte 17 doesn't come back exactly from its light" ]
    problems report `shouldEqual` [ "gammaSrgb: byte 17 doesn't come back exactly from its light" ]
    exactArithmetic report `shouldEqual` false
