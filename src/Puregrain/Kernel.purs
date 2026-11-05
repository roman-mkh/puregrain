-- | Error-diffusion kernels: where each pixel's quantization error goes,
-- | and in what shares.
-- |
-- | Use a ready-made kernel, or build your own from a list of offsets
-- | with `fromOffsets`, which checks it. The ready-made ones:
-- | `floydSteinberg`, `atkinson`, `jarvisJudiceNinke`, `stucki`, `burkes`,
-- | the Sierras `sierra3`, `sierra2` and `sierraLite`, `fan`, `shiauFan`
-- | and `shiauFan2`; `noDiffusion` for none. Each one's table, its source
-- | and what it suits:
-- | [docs/error-diffusion.md](https://github.com/roman-mkh/puregrain/blob/master/docs/error-diffusion.md).
module Puregrain.Kernel
  ( Offset
  , Kernel
  , fromOffsets
  , offsets
  , floydSteinberg
  , atkinson
  , jarvisJudiceNinke
  , stucki
  , burkes
  , sierra3
  , sierra2
  , sierraLite
  , fan
  , shiauFan
  , shiauFan2
  , noDiffusion
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Number (isFinite)
import Data.Tuple (Tuple(..))

-- | One neighbour that gets a share of a pixel's error.
-- |
-- | - `dx`: columns to the right; negative to the left.
-- | - `dy`: rows down.
-- | - `weight`: the share of the error.
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

-- | Checks a list of offsets and makes it a kernel.
-- |
-- | - `Array Offset`: the neighbours and their shares.
-- |
-- | `Left` says which offset breaks which rule (offsets counted from 0):
-- |
-- | - every offset must point to a pixel not yet processed, in row-by-row
-- |   scan order: a later row (`dy > 0`), or the same row further right
-- |   (`dy == 0`, `dx > 0`);
-- | - every weight must be a finite number (not NaN or infinite);
-- | - no two offsets may point to the same neighbour.
-- |
-- | The weights usually add up to 1, but needn't: Atkinson's add up to
-- | 3/4 on purpose. An empty list is valid: it's `noDiffusion`.
-- |
-- | ```purescript
-- | -- half of the error to the right, half down
-- | fromOffsets [ { dx: 1, dy: 0, weight: 0.5 }, { dx: 0, dy: 1, weight: 0.5 } ]
-- | ```
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
-- | the smoothest texture, at about 2.5 times Floyd–Steinberg's cost.
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

-- | Stucki (Peter Stucki, IBM Zurich, 1981): 12 neighbours over the next 2
-- | rows, like Jarvis–Judice–Ninke, with weights that give a clean, sharp
-- | result.
stucki :: Kernel
stucki = Kernel
  [ { dx: 1, dy: 0, weight: 8.0 / 42.0 }
  , { dx: 2, dy: 0, weight: 4.0 / 42.0 }

  , { dx: -2, dy: 1, weight: 2.0 / 42.0 }
  , { dx: -1, dy: 1, weight: 4.0 / 42.0 }
  , { dx: 0,  dy: 1, weight: 8.0 / 42.0 }
  , { dx: 1,  dy: 1, weight: 4.0 / 42.0 }
  , { dx: 2,  dy: 1, weight: 2.0 / 42.0 }

  , { dx: -2, dy: 2, weight: 1.0 / 42.0 }
  , { dx: -1, dy: 2, weight: 2.0 / 42.0 }
  , { dx: 0,  dy: 2, weight: 4.0 / 42.0 }
  , { dx: 1,  dy: 2, weight: 2.0 / 42.0 }
  , { dx: 2,  dy: 2, weight: 1.0 / 42.0 }
  ]

-- | Burkes (Daniel Burkes, 1988): Stucki without its last row, so 7
-- | neighbours over the next row: a little less clean, at a lower cost.
burkes :: Kernel
burkes = Kernel
  [ { dx: 1, dy: 0, weight: 8.0 / 32.0 }
  , { dx: 2, dy: 0, weight: 4.0 / 32.0 }

  , { dx: -2, dy: 1, weight: 2.0 / 32.0 }
  , { dx: -1, dy: 1, weight: 4.0 / 32.0 }
  , { dx: 0,  dy: 1, weight: 8.0 / 32.0 }
  , { dx: 1,  dy: 1, weight: 4.0 / 32.0 }
  , { dx: 2,  dy: 1, weight: 2.0 / 32.0 }
  ]

-- | Sierra 3 (Frankie Sierra, 1989–1990; also "Sierra" or "three-row
-- | Sierra"): 10 neighbours over the next 2 rows, for results like
-- | Jarvis–Judice–Ninke's with fewer neighbours.
sierra3 :: Kernel
sierra3 = Kernel
  [ { dx: 1, dy: 0, weight: 5.0 / 32.0 }
  , { dx: 2, dy: 0, weight: 3.0 / 32.0 }

  , { dx: -2, dy: 1, weight: 2.0 / 32.0 }
  , { dx: -1, dy: 1, weight: 4.0 / 32.0 }
  , { dx: 0,  dy: 1, weight: 5.0 / 32.0 }
  , { dx: 1,  dy: 1, weight: 4.0 / 32.0 }
  , { dx: 2,  dy: 1, weight: 2.0 / 32.0 }

  , { dx: -1, dy: 2, weight: 2.0 / 32.0 }
  , { dx: 0,  dy: 2, weight: 3.0 / 32.0 }
  , { dx: 1,  dy: 2, weight: 2.0 / 32.0 }
  ]

-- | Sierra 2 (Frankie Sierra, 1989–1990; also "two-row Sierra"): 7
-- | neighbours over the next row, a faster Sierra 3.
sierra2 :: Kernel
sierra2 = Kernel
  [ { dx: 1, dy: 0, weight: 4.0 / 16.0 }
  , { dx: 2, dy: 0, weight: 3.0 / 16.0 }

  , { dx: -2, dy: 1, weight: 1.0 / 16.0 }
  , { dx: -1, dy: 1, weight: 2.0 / 16.0 }
  , { dx: 0,  dy: 1, weight: 3.0 / 16.0 }
  , { dx: 1,  dy: 1, weight: 2.0 / 16.0 }
  , { dx: 2,  dy: 1, weight: 1.0 / 16.0 }
  ]

-- | Sierra Lite (Frankie Sierra, 1989–1990; also "Filter Lite" or
-- | "Sierra-2-4A"): 3 neighbours, one fewer than Floyd–Steinberg, for
-- | similar results.
sierraLite :: Kernel
sierraLite = Kernel
  [ { dx: 1,  dy: 0, weight: 2.0 / 4.0 }
  , { dx: -1, dy: 1, weight: 1.0 / 4.0 }
  , { dx: 0,  dy: 1, weight: 1.0 / 4.0 }
  ]

-- | Fan (Zhigang Fan, 1993): Floyd–Steinberg's 4 neighbours with one weight
-- | moved, its 1/16 from below-right to two columns left.
fan :: Kernel
fan = Kernel
  [ { dx: 1,  dy: 0, weight: 7.0 / 16.0 }
  , { dx: -2, dy: 1, weight: 1.0 / 16.0 }
  , { dx: -1, dy: 1, weight: 3.0 / 16.0 }
  , { dx: 0,  dy: 1, weight: 5.0 / 16.0 }
  ]

-- | Shiau–Fan (Jeng-Nan Shiau and Zhigang Fan, 1993): 4 neighbours, with
-- | weights in eighths, made to reduce the "worm" patterns of
-- | Floyd–Steinberg.
shiauFan :: Kernel
shiauFan = Kernel
  [ { dx: 1,  dy: 0, weight: 4.0 / 8.0 }
  , { dx: -2, dy: 1, weight: 1.0 / 8.0 }
  , { dx: -1, dy: 1, weight: 1.0 / 8.0 }
  , { dx: 0,  dy: 1, weight: 2.0 / 8.0 }
  ]

-- | Shiau–Fan 2 (Jeng-Nan Shiau and Zhigang Fan, 1993): the same aim with 5
-- | neighbours, reaching three columns to the left.
shiauFan2 :: Kernel
shiauFan2 = Kernel
  [ { dx: 1,  dy: 0, weight: 8.0 / 16.0 }
  , { dx: -3, dy: 1, weight: 1.0 / 16.0 }
  , { dx: -2, dy: 1, weight: 1.0 / 16.0 }
  , { dx: -1, dy: 1, weight: 2.0 / 16.0 }
  , { dx: 0,  dy: 1, weight: 4.0 / 16.0 }
  ]

-- | No neighbours: no error is passed on, so each pixel is quantized on
-- | its own. With `Puregrain.Ordered`, that's pure ordered dithering;
-- | with `threshold` or `nearestLevel`, plain rounding to a level.
noDiffusion :: Kernel
noDiffusion = Kernel []
