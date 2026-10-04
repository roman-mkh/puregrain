-- | Ordered dithering: a quantizer whose decision between two
-- | neighbouring levels depends on the pixel's position, through a
-- | repeating grid of thresholds — a threshold map. The best known one is
-- | the Bayer matrix (Bryce E. Bayer, Kodak, 1973).
-- |
-- | It's an ordinary `Quantize`, so it plugs into the unchanged
-- | `ditherImage`. With the empty kernel (`[]`, no error passed on), that
-- | gives pure ordered dithering; with any other kernel, the hybrid
-- | "threshold modulation": error diffusion keeps the tones right, and
-- | the map decides where the dots land. Background, formulas and what to
-- | look for: docs/ordered-dithering.md.
module Dither.Ordered
  ( ThresholdMap
  , bayer
  , bayerMatrix
  , compileThresholdMap
  , thresholdAt
  , ordered
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Either (Either(..))
import Data.Foldable (foldl)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..), maybe)
import Dither.Pixel (Quantize(..))
import Partial.Unsafe (unsafePartial)

-- | A threshold map, checked and precomputed: a `width` × `height` grid
-- | of thresholds, each strictly between 0 and 1, repeated across the
-- | image. Built only by `bayer` or `compileThresholdMap` (the constructor
-- | isn't exported), so every one is rectangular and non-empty, and
-- | `thresholdAt` can look one up in O(1).
newtype ThresholdMap = ThresholdMap
  { width :: Int
  , height :: Int
  , thresholds :: Array Number -- row-major, width × height entries
  }

-- | The ranks of the `n` × `n` Bayer matrix, for `n` a power of 2 (1, 2,
-- | 4, 8, …); `Nothing` for any other `n`. Built by the standard
-- | recursion from the 1 × 1 matrix `[[0]]`:
-- |
-- | ```
-- | M₂ₙ = | 4·Mₙ + 0   4·Mₙ + 2 |
-- |       | 4·Mₙ + 3   4·Mₙ + 1 |
-- | ```
-- |
-- | so `bayerMatrix 2 == Just [[0, 2], [3, 1]]`, and every rank from 0 to
-- | n² − 1 appears exactly once. The result has n² entries: mind the size
-- | for large `n`.
bayerMatrix :: Int -> Maybe (Array (Array Int))
bayerMatrix n = if isPowerOf2 n then Just (build n) else Nothing
  where
    build m
      | m <= 1 = [ [ 0 ] ]
      | otherwise =
          let
            half = build (m / 2)
            quadrant offset = map (map (\rank -> 4 * rank + offset)) half
          in
            Array.zipWith (<>) (quadrant 0) (quadrant 2)
              <> Array.zipWith (<>) (quadrant 3) (quadrant 1)

isPowerOf2 :: Int -> Boolean
isPowerOf2 n
  | n == 1 = true
  | n < 1 || n `mod` 2 /= 0 = false
  | otherwise = isPowerOf2 (n / 2)

-- | The `n` × `n` Bayer threshold map, for `n` a power of 2 (1, 2, 4, 8,
-- | …); `Nothing` for any other `n`. Its thresholds are
-- | `(rank + 0.5) / n²` (see `compileThresholdMap`). `bayer 1` is the
-- | trivial map, 0.5 everywhere: `ordered (bayer 1)` then picks the
-- | nearer level, like `nearestLevel`.
bayer :: Int -> Maybe ThresholdMap
bayer n = fromRanks <$> bayerMatrix n

-- | Checks a custom map of ranks and turns it into thresholds. The ranks
-- | say in which order the cells turn on as the input rises; the map
-- | needn't be square, and ranks may repeat or skip values (clustered-dot
-- | screens, blue-noise masks). Each cell's threshold is
-- | `(rank + 0.5) / (maxRank + 1)`, strictly between 0 and 1.
-- |
-- | `Left` says what's wrong: no rows, an empty row, rows of different
-- | lengths, or a negative rank (rows and columns counted from 0).
compileThresholdMap :: Array (Array Int) -> Either String ThresholdMap
compileThresholdMap rows = case Array.head rows of
  Nothing -> Left "a threshold map needs at least one row"
  Just first
    | Array.null first -> Left "a threshold map's rows need at least one entry"
    | otherwise ->
        let
          width = Array.length first
        in
          case Array.findIndex (\row -> Array.length row /= width) rows of
            Just i ->
              Left
                ( "all rows of a threshold map must have the same length: row 0 has "
                    <> show width
                    <> " entries, row "
                    <> show i
                    <> " has "
                    <> show (maybe 0 Array.length (Array.index rows i))
                )
            Nothing -> case firstNegative of
              Just { row, column, rank } ->
                Left
                  ( "ranks in a threshold map must not be negative: row "
                      <> show row
                      <> ", column "
                      <> show column
                      <> " is "
                      <> show rank
                  )
              Nothing -> Right (fromRanks rows)
  where
    firstNegative = Array.findMap identity (Array.mapWithIndex negativeIn rows)
    negativeIn row cells =
      Array.findIndex (_ < 0) cells <#> \column ->
        { row, column, rank: unsafePartial (Array.unsafeIndex cells column) }

-- | Ranks to thresholds, for ranks already known to be valid.
fromRanks :: Array (Array Int) -> ThresholdMap
fromRanks rows = ThresholdMap
  { width: maybe 0 Array.length (Array.head rows)
  , height: Array.length rows
  , thresholds: map (\rank -> (toNumber rank + 0.5) / count) flat
  }
  where
    flat = Array.concat rows
    count = toNumber (foldl max 0 flat + 1)

-- | The threshold at a pixel's position: the map repeats across the
-- | image, so column `x` uses the map's column `x mod width`, and row `y`
-- | its row `y mod height`. Takes any record with `x` and `y`, such as a
-- | quantizer's `Context`.
thresholdAt :: forall r. ThresholdMap -> { x :: Int, y :: Int | r } -> Number
thresholdAt (ThresholdMap m) { x, y } =
  unsafePartial (Array.unsafeIndex m.thresholds ((y `mod` m.height) * m.width + x `mod` m.width))

-- | Ordered dithering over the given levels. For a value `v` between two
-- | neighbouring levels `lo` < `hi`, it picks `hi` exactly when the
-- | fraction of the way from `lo` to `hi`, `(v − lo) / (hi − lo)`, is
-- | above the pixel's threshold; otherwise `lo`. With levels 0 and 255
-- | this is classic 1-bit Bayer dithering. Color: lift it with
-- | `perChannel`, which hands every channel the same position.
-- |
-- | The levels are sorted once, here, not per pixel, and needn't be
-- | given in order. Total for any input: a value at a level stays that
-- | level, and values beyond the lowest or highest level snap to it, as
-- | with `nearestLevel`. That matters in the hybrid with error diffusion,
-- | where accumulated error pushes values past the ends.
ordered :: ThresholdMap -> NonEmptyArray Number -> Quantize Number
ordered thresholdMap levels = Quantize \ctx v -> between (thresholdAt thresholdMap ctx) v
  where
    sorted = NEA.toArray (NEA.sort levels)
    lastIndex = Array.length sorted - 1
    level i = unsafePartial (Array.unsafeIndex sorted i)
    lowest = level 0
    highest = level lastIndex

    between t v
      | lastIndex == 0 || v <= lowest = lowest
      | v >= highest = highest
      | otherwise = go 1
      where
        -- Invariant: level (i − 1) <= v. Stops at the first level above
        -- v; the `i >= lastIndex` guard also ends the scan for a NaN.
        go i
          | i >= lastIndex || v < level i = pick (level (i - 1)) (level i)
          | otherwise = go (i + 1)
        -- (v − lo) / (hi − lo) > t, without the division.
        pick lo hi = if v - lo > t * (hi - lo) then hi else lo
