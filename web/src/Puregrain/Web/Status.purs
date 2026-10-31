-- | The run's state, and what the picture area and the bar show for it
-- | (decision 30 in web/ROADMAP.md): which picture shows, when the
-- | progress shows, and the bar's message about the run. Pure, so specs
-- | test it.
module Puregrain.Web.Status
  ( Run(..)
  , progressDelay
  , held
  , resultShows
  , RunNote(..)
  , runNote
  ) where

import Prelude

import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe(..))
import Data.Show.Generic (genericShow)
import Puregrain.Web.Message (FileBytes)

-- | The dithering: none, running, held, finished, cancelled or failed.
-- |
-- | - `Running`: the rows done of all, when it started, and the time left
-- |   once it's worth showing (decision 23); `progressShown` once it has
-- |   gone on for `progressDelay`; `keepsPrevious` when the result before
-- |   it stays on show meanwhile.
-- | - `Held`: a run waiting for the phone's settings panel to close
-- |   (decision 29), keeping the result before it on show if that one
-- |   shows.
-- | - `Finished`: a machine's files, and whether saving the PNG failed.
data Run
  = Idle
  | Running
      { done :: Int
      , total :: Int
      , started :: Number
      , left :: Maybe Number
      , progressShown :: Boolean
      , keepsPrevious :: Boolean
      }
  | Held { keepsPrevious :: Boolean }
  | Finished { files :: Array FileBytes, saveFailed :: Boolean }
  | Cancelled
  | RunFailed String

-- | How long a run goes on, in milliseconds, before its progress shows: a
-- | second, Jakob Nielsen's limit for the flow of thought; below it, no
-- | feedback is needed (decision 30 B).
progressDelay :: Number
progressDelay = 1000.0

-- | Whether the result shows over the original, split with it: a
-- | finished run's result, and during a run the result before it, so
-- | that nothing flickers (decision 30 B). Not before a picture's first
-- | result, nor after Cancel or a failure: then no result matches the
-- | settings, and the original shows.
-- |
-- | A new run keeps the result before it exactly when that one shows,
-- | so its `keepsPrevious` is `resultShows` of the run it replaces.
resultShows :: Run -> Boolean
resultShows = case _ of
  Finished _ -> true
  Running r -> r.keepsPrevious
  Held r -> r.keepsPrevious
  _ -> false

-- | The run that waits while the phone's settings panel is open, in place
-- | of this one: it starts when the panel closes, and keeps showing what
-- | this one shows meanwhile.
held :: Run -> Run
held run = Held { keepsPrevious: resultShows run }

-- | What the bar says about the run.
data RunNote
  = OriginalShown
  | Progress { done :: Int, total :: Int, left :: Maybe Number }
  | RunCancelled
  | DitherFailed String
  | SaveFailed

derive instance Eq RunNote
derive instance Generic RunNote _
instance Show RunNote where
  show = genericShow

-- | The bar's message about the run, if any: with every setting at
-- | "none", that the original is shown; the progress once it shows; the
-- | end of a cancelled or failed run; a failed save. Nothing while a run
-- | is in its first second or held, or once it's done.
runNote :: Run -> Maybe RunNote
runNote = case _ of
  Idle -> Just OriginalShown
  Running r ->
    if r.progressShown then Just (Progress { done: r.done, total: r.total, left: r.left })
    else Nothing
  Held _ -> Nothing
  Finished r -> if r.saveFailed then Just SaveFailed else Nothing
  Cancelled -> Just RunCancelled
  RunFailed reason -> Just (DitherFailed reason)
