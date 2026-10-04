-- | Error-diffusion kernels: where each pixel's quantization error goes,
-- | and in what shares.
-- |
-- | Use a ready-made kernel (`floydSteinberg`, `atkinson`,
-- | `jarvisJudiceNinke`, or `noDiffusion` for none), or build your own
-- | from a list of offsets with `fromOffsets`, which checks it.
module Puregrain.Kernel
  ( Offset
  , Kernel
  , fromOffsets
  , offsets
  , floydSteinberg
  , atkinson
  , jarvisJudiceNinke
  , noDiffusion
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Number (isFinite)
import Data.Tuple (Tuple(..))

-- | One neighbour that receives a share of a pixel's error: `dx` columns
-- | to the right (negative: to the left) and `dy` rows down, with the
-- | share `weight`.
type Offset =
  { dx     :: Int
  , dy     :: Int
  , weight :: Number
  }

-- | A checked list of neighbours. Build one with `fromOffsets`, or use a
-- | ready-made one. Opaque, so every kernel `ditherImage` gets is valid.
newtype Kernel = Kernel (Array Offset)

derive newtype instance Eq Kernel
derive newtype instance Show Kernel

-- | Checks a list of offsets and makes it a kernel:
-- |
-- | - every offset points to a pixel not yet processed, in row-by-row
-- |   scan order: a later row (`dy > 0`), or the same row further right
-- |   (`dy == 0`, `dx > 0`);
-- | - every weight is a finite number (not NaN or infinite);
-- | - no two offsets point to the same neighbour.
-- |
-- | The weights usually add up to 1, but needn't: Atkinson's add up to
-- | 3/4 on purpose. An empty list is valid: it's `noDiffusion`.
-- |
-- | `Left` says which offset breaks which rule (offsets counted from 0).
fromOffsets :: Array Offset -> Either String Kernel
fromOffsets list =
  case Array.findMap identity (Array.mapWithIndex offsetProblem list) of
    Just problem -> Left problem
    Nothing -> case firstDuplicate of
      Just { first, second, offset } ->
        Left
          ( "offsets " <> show first <> " and " <> show second <> " both point to " <> describe offset
              <> ": each neighbour may appear only once"
          )
      Nothing -> Right (Kernel list)
  where
    offsetProblem i o
      | not (o.dy > 0 || (o.dy == 0 && o.dx > 0)) =
          Just
            ( "offset " <> show i <> " (" <> describe o <> ") doesn't point forward: an offset must point "
                <> "to a later row (dy > 0), or further right in the same row (dy = 0, dx > 0)"
            )
      | not (isFinite o.weight) =
          Just ("offset " <> show i <> " (" <> describe o <> ") has the weight " <> show o.weight <> "; weights must be finite numbers")
      | otherwise = Nothing

    describe o = "dx " <> show o.dx <> ", dy " <> show o.dy

    -- The first offset that repeats an earlier one, with both indices.
    firstDuplicate = Array.findMap identity do
      Tuple second offset <- Array.mapWithIndex Tuple list
      pure
        ( Array.findIndex (\p -> p.dx == offset.dx && p.dy == offset.dy) (Array.take second list)
            <#> \first -> { first, second, offset }
        )

-- | The kernel's offsets, as given to `fromOffsets`.
offsets :: Kernel -> Array Offset
offsets (Kernel list) = list

-- | Floyd–Steinberg (1976): 4 neighbours, the classic.
floydSteinberg :: Kernel
floydSteinberg = Kernel
  [ { dx: 1,  dy: 0, weight: 7.0 / 16.0 }
  , { dx: -1, dy: 1, weight: 3.0 / 16.0 }
  , { dx: 0,  dy: 1, weight: 5.0 / 16.0 }
  , { dx: 1,  dy: 1, weight: 1.0 / 16.0 }
  ]

-- | Atkinson (Apple, 1980s): 6 neighbours over the next 2 rows, each
-- | getting 1/8, so only 3/4 of the error is passed on: crisper and
-- | higher in contrast, at the cost of detail in dark and light tones.
atkinson :: Kernel
atkinson = Kernel
  [ { dx: 1,  dy: 0, weight: 1.0 / 8.0 }
  , { dx: 2,  dy: 0, weight: 1.0 / 8.0 }
  , { dx: -1, dy: 1, weight: 1.0 / 8.0 }
  , { dx: 0,  dy: 1, weight: 1.0 / 8.0 }
  , { dx: 1,  dy: 1, weight: 1.0 / 8.0 }
  , { dx: 0,  dy: 2, weight: 1.0 / 8.0 }
  ]

-- | Jarvis–Judice–Ninke (1976): 12 neighbours over the next 2 rows, for
-- | the smoothest texture, at about three times Floyd–Steinberg's cost.
jarvisJudiceNinke :: Kernel
jarvisJudiceNinke = Kernel
  [ { dx: 1, dy: 0, weight: 7.0 / 48.0 }
  , { dx: 2, dy: 0, weight: 5.0 / 48.0 }

  , { dx: -2, dy: 1, weight: 3.0 / 48.0 }
  , { dx: -1, dy: 1, weight: 5.0 / 48.0 }
  , { dx: 0,  dy: 1, weight: 7.0 / 48.0 }
  , { dx: 1,  dy: 1, weight: 5.0 / 48.0 }
  , { dx: 2,  dy: 1, weight: 3.0 / 48.0 }

  , { dx: -2, dy: 2, weight: 1.0 / 48.0 }
  , { dx: -1, dy: 2, weight: 3.0 / 48.0 }
  , { dx: 0,  dy: 2, weight: 5.0 / 48.0 }
  , { dx: 1,  dy: 2, weight: 3.0 / 48.0 }
  , { dx: 2,  dy: 2, weight: 1.0 / 48.0 }
  ]

-- | No neighbours: no error is passed on, so each pixel is quantized on
-- | its own. With `Puregrain.Ordered`, that's pure ordered dithering;
-- | with `threshold` or `nearestLevel`, plain rounding to a level.
noDiffusion :: Kernel
noDiffusion = Kernel []
