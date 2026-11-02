-- | The time a run has left (decision 23 in web/ROADMAP.md): from the
-- | rows done so far and the time they took, shown once the predicted
-- | total is over 10 s, Jakob Nielsen's limit of attention, and kept from
-- | then on; rounded to steps that don't flicker. Pure, apart from the
-- | clock, so specs test it.
module Puregrain.Web.Estimate
  ( Progress
  , clock
  , timeLeft
  , worthShowing
  , next
  , TimeLeft
  , rounded
  ) where

import Prelude

import Data.DateTime.Instant (unInstant)
import Data.Int (round, toNumber)
import Data.Maybe (Maybe(..), isJust)
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Now (now)

-- | A run's progress: the time since it started, in milliseconds, and its
-- | rows done of all.
type Progress = { elapsed :: Number, done :: Int, total :: Int }

-- | Now, in milliseconds.
clock :: Effect Number
clock = (\(Milliseconds ms) -> ms) <<< unInstant <$> now

-- | The time left, in milliseconds, at the pace of the rows so far: time
-- | so far ÷ rows done × rows left. Nothing before the first row is done.
timeLeft :: Progress -> Maybe Number
timeLeft p =
  if p.done <= 0 then Nothing
  else Just (p.elapsed / toNumber p.done * toNumber (p.total - p.done))

-- | Whether the run is predicted to take over 10 s in all.
worthShowing :: Progress -> Boolean
worthShowing p = p.done > 0 && p.elapsed / toNumber p.done * toNumber p.total > 10000.0

-- | The time left to show after a progress report, given what was shown
-- | before: none until the run is worth an estimate, then always one, so
-- | it doesn't come and go near the limit.
next :: Maybe Number -> Progress -> Maybe Number
next shown p = if isJust shown || worthShowing p then timeLeft p else Nothing

-- | A time left as it's shown: minutes and seconds, both 0 when it's
-- | only a few seconds.
type TimeLeft = { minutes :: Int, seconds :: Int }

-- | Milliseconds left in steps: under a minute to the nearest 5 s, up to
-- | 10 minutes to the nearest 10 s, beyond that to the nearest minute.
-- |
-- | ```purescript
-- | rounded 47300.0 == { minutes: 0, seconds: 45 }
-- | rounded 150000.0 == { minutes: 2, seconds: 30 }
-- | ```
rounded :: Number -> TimeLeft
rounded ms =
  -- (`if`, not guards: a `where` after guards belongs to the last one.)
  if seconds < 60.0 then split (5 * round (seconds / 5.0))
  else if seconds < 600.0 then split (10 * round (seconds / 10.0))
  else { minutes: round (seconds / 60.0), seconds: 0 }
  where
  seconds = ms / 1000.0
  split s = { minutes: s / 60, seconds: s `mod` 60 }
