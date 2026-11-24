module Test.Puregrain.Web.StatusSpec (spec) where

import Prelude

import Data.Maybe (Maybe(..))
import Puregrain.Web.Status (EngineCheck(..), LoadFailure(..), Run(..), RunNote(..), engineCheckName, held, progressDelay, resultShows, runNote)
import Puregrain.Web.Text (texts)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = describe "Puregrain.Web.Status" do
  it "names the engine check's states on the page's root, for check:web" do
    map engineCheckName [ EngineChecking, EnginePassed, EngineFailed [ "x" ], EngineNotRun ]
      `shouldEqual` [ "checking", "passed", "failed", "not-run" ]

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

  it "shows a run's progress only once it has gone on for a second, at once on a picture of 2 megapixels or more" do
    map progressDelay [ 320 * 200, 1999999 ] `shouldEqual` [ 1000.0, 1000.0 ]
    map progressDelay [ 2000000, 4096 * 3072 ] `shouldEqual` [ 0.0, 0.0 ]
    runNote (running { progressShown: false, keepsPrevious: true }) `shouldEqual` Nothing
    runNote (running { progressShown: true, keepsPrevious: true }) `shouldEqual` Just (Progress { done: 10, total: 200, left: Nothing })

  it "holds a run while the phone's panel is open, showing what the run before it showed" do
    -- A change in the panel: the result shown stays, the original stays.
    resultShows (held finished) `shouldEqual` true
    resultShows (held (running { progressShown: true, keepsPrevious: true })) `shouldEqual` true
    resultShows (held (running { progressShown: true, keepsPrevious: false })) `shouldEqual` false
    resultShows (held Idle) `shouldEqual` false
    resultShows (held Cancelled) `shouldEqual` false
    -- Held again by a further change: unchanged.
    resultShows (held (held finished)) `shouldEqual` true
    -- The run that starts at the panel's closing keeps it on show too.
    resultShows (running { progressShown: false, keepsPrevious: resultShows (held finished) }) `shouldEqual` true
    -- Nothing to say about it, behind the panel.
    runNote (held finished) `shouldEqual` Nothing

  it "says what the bar says in each state" do
    runNote Idle `shouldEqual` Just OriginalShown
    runNote finished `shouldEqual` Nothing
    runNote (Finished { files: [], saveFailed: true }) `shouldEqual` Just SaveFailed
    runNote Cancelled `shouldEqual` Just RunCancelled
    runNote (RunFailed "out of memory") `shouldEqual` Just (DitherFailed "out of memory")
    texts.originalShown `shouldEqual` "The original is shown. Choose colors or a method to dither it."
    texts.cancelled `shouldEqual` "Cancelled; the original is shown."
    texts.loadFailure (NotAPicture "notes.txt") true `shouldEqual` "notes.txt isn't a picture; the current one stays."

  it "says why a picture couldn't be loaded, the same with one shown or not, except a file's" do
    texts.loadFailure (NotAPicture "notes.txt") false `shouldEqual` "notes.txt isn't a picture."
    map (\kept -> texts.loadFailure SampleFailed kept) [ false, true ]
      `shouldEqual` [ "The sample picture couldn't be loaded.", "The sample picture couldn't be loaded." ]
    texts.loadFailure NothingToPaste false
      `shouldEqual` "There's no picture on the clipboard: copy one first, with \"Copy image\" on a web page, or take a screenshot."
    texts.loadFailure ClipboardRefused true `shouldEqual` "The browser didn't let the page read the clipboard. If it shows a \"Paste\" button by the pointer, click that one."
