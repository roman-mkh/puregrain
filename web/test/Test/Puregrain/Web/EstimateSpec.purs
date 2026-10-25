module Test.Puregrain.Web.EstimateSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Estimate (next, rounded, timeLeft, worthShowing)
import Puregrain.Web.Text (texts)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Estimate" do
  it "gives the time left at the pace of the rows so far, once a row is done" do
    timeLeft { elapsed: 0.0, done: 0, total: 100 } `shouldEqual` Nothing
    timeLeft { elapsed: 2000.0, done: 10, total: 110 } `shouldEqual` Just 20000.0

  it "is worth showing for a run predicted to take over 10 s" do
    worthShowing { elapsed: 1000.0, done: 10, total: 100 } `shouldEqual` false
    worthShowing { elapsed: 1001.0, done: 10, total: 100 } `shouldEqual` true
    worthShowing { elapsed: 5000.0, done: 0, total: 100 } `shouldEqual` false

  it "starts showing when it's worth it, and then keeps showing" do
    next Nothing { elapsed: 500.0, done: 10, total: 100 } `shouldEqual` Nothing
    next Nothing { elapsed: 2000.0, done: 10, total: 100 } `shouldEqual` Just 18000.0
    -- the pace picked up, below the limit now: still shown
    next (Just 18000.0) { elapsed: 1000.0, done: 50, total: 100 } `shouldEqual` Just 1000.0

  it "rounds to steps: 5 s under a minute, 10 s up to 10 minutes, whole minutes beyond" do
    rounded 2400.0 `shouldEqual` { minutes: 0, seconds: 0 }
    rounded 2600.0 `shouldEqual` { minutes: 0, seconds: 5 }
    rounded 47300.0 `shouldEqual` { minutes: 0, seconds: 45 }
    rounded 57500.0 `shouldEqual` { minutes: 1, seconds: 0 }
    rounded 61000.0 `shouldEqual` { minutes: 1, seconds: 0 }
    rounded 125000.0 `shouldEqual` { minutes: 2, seconds: 10 }
    rounded 150000.0 `shouldEqual` { minutes: 2, seconds: 30 }
    rounded 595000.0 `shouldEqual` { minutes: 10, seconds: 0 }
    rounded 754000.0 `shouldEqual` { minutes: 13, seconds: 0 }

  it "reads as minutes and seconds, or a few seconds at the end" do
    texts.timeLeft { minutes: 0, seconds: 45 } `shouldEqual` "about 45 s left"
    texts.timeLeft { minutes: 2, seconds: 30 } `shouldEqual` "about 2 min 30 s left"
    texts.timeLeft { minutes: 13, seconds: 0 } `shouldEqual` "about 13 min left"
    texts.timeLeft { minutes: 0, seconds: 0 } `shouldEqual` "a few seconds left"
