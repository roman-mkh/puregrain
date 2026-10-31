module Test.Puregrain.Web.StatusSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Status (Run(..), RunNote(..), progressDelay, resultShows, runNote)
import Puregrain.Web.Text (texts)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Status" do
  let
    running r = Running { done: 10, total: 200, started: 0.0, left: Nothing, progressShown: r.progressShown, keepsPrevious: r.keepsPrevious }
    finished = Finished { files: [], saveFailed: false }

  it "shows the result when the run is done, and during the next run until that one is" do
    resultShows finished `shouldEqual` true
    -- A new run keeps the result before it exactly when that one shows.
    let next = running { progressShown: false, keepsPrevious: resultShows finished }
    resultShows next `shouldEqual` true
    resultShows (running { progressShown: true, keepsPrevious: resultShows next }) `shouldEqual` true

  it "shows the original for a picture's first run, after Cancel, after a failure, and with every setting at none" do
    resultShows (running { progressShown: false, keepsPrevious: resultShows Idle }) `shouldEqual` false
    resultShows Cancelled `shouldEqual` false
    resultShows (running { progressShown: false, keepsPrevious: resultShows Cancelled }) `shouldEqual` false
    resultShows (RunFailed "out of memory") `shouldEqual` false
    resultShows (running { progressShown: false, keepsPrevious: resultShows (RunFailed "out of memory") }) `shouldEqual` false
    resultShows Idle `shouldEqual` false

  it "shows a run's progress only once it has gone on for a second" do
    progressDelay `shouldEqual` 1000.0
    runNote (running { progressShown: false, keepsPrevious: true }) `shouldEqual` Nothing
    runNote (running { progressShown: true, keepsPrevious: true }) `shouldEqual` Just (Progress { done: 10, total: 200, left: Nothing })

  it "says what the bar says in each state" do
    runNote Idle `shouldEqual` Just OriginalShown
    runNote finished `shouldEqual` Nothing
    runNote (Finished { files: [], saveFailed: true }) `shouldEqual` Just SaveFailed
    runNote Cancelled `shouldEqual` Just RunCancelled
    runNote (RunFailed "out of memory") `shouldEqual` Just (DitherFailed "out of memory")
    texts.originalShown `shouldEqual` "The original is shown. Choose colors or a method to dither it."
    texts.cancelled `shouldEqual` "Cancelled; the original is shown."
    texts.notAPictureKept "notes.txt" `shouldEqual` "notes.txt isn't a picture; the current one stays."
