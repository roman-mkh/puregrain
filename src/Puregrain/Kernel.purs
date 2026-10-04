-- | Error-diffusion kernels: where each pixel's quantization error goes,
-- | and in what shares.
module Puregrain.Kernel
  ( Offset
  , Kernel
  , floydSteinberg
  , atkinson
  , jarvisJudiceNinke
  ) where

import Prelude

-- | One neighbour that receives a share of a pixel's error: `dx` columns
-- | to the right (negative: to the left) and `dy` rows down, with the
-- | share `weight`.
type Offset =
  { dx     :: Int
  , dy     :: Int
  , weight :: Number
  }

-- | A list of neighbours. Every offset must point to a pixel not yet
-- | processed, in row-by-row scan order: a later row (`dy > 0`), or the
-- | same row further right (`dy == 0`, `dx > 0`). The weights usually add
-- | up to 1, but needn't. The empty kernel `[]` passes no error on at
-- | all: each pixel is quantized on its own (used for pure ordered
-- | dithering, see `Puregrain.Ordered`).
type Kernel = Array Offset

-- | Floyd–Steinberg (1976): 4 neighbours, the classic.
floydSteinberg :: Kernel
floydSteinberg =
  [ { dx: 1,  dy: 0, weight: 7.0 / 16.0 }
  , { dx: -1, dy: 1, weight: 3.0 / 16.0 }
  , { dx: 0,  dy: 1, weight: 5.0 / 16.0 }
  , { dx: 1,  dy: 1, weight: 1.0 / 16.0 }
  ]

-- | Atkinson (Apple, 1980s): 6 neighbours over the next 2 rows, each
-- | getting 1/8, so only 3/4 of the error is passed on: crisper and
-- | higher in contrast, at the cost of detail in dark and light tones.
atkinson :: Kernel
atkinson =
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
jarvisJudiceNinke =
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
