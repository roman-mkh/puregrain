module Test.Puregrain.Reference where

import Prelude

import Control.Monad.ST (ST, run)
import Data.Array as Array
import Data.Array.ST as STArray
import Data.Maybe (Maybe(..))
import Puregrain.Kernel (Kernel, offsets)
import Puregrain.Pixel (class Scalable, scale)
import Puregrain.Quantize (Quantize, runQuantize)

-- | Flattens a rectangular Array (Array a) into a single Array a,
-- | row-major (row 0 first, then row 1, ...).
flatten :: forall a. Array (Array a) -> Array a
flatten = Array.concat

-- | Splits a flat, row-major Array a back into `height` rows of
-- | `width` each. Assumes `Array.length flat == width * height`.
unflatten :: forall a. Int -> Int -> Array a -> Array (Array a)
unflatten width height flat =
  map (\y -> Array.slice (y * width) (y * width + width) flat) (Array.range 0 (height - 1))

-- | A direct, textbook implementation of error-diffusion dithering,
-- | independent of this library's `Fifo`/`DelayLine`/padding machinery.
-- | Used as a QuickCheck oracle: `ditherImage` (and each `Fifo`
-- | backend) is expected to produce EXACTLY the same result as this
-- | function for any kernel/image, since they implement the same
-- | mathematics via a different (padding/FIFO-based, streaming) route.
-- |
-- | Deliberately simple and easy to verify by hand: one mutable 2D
-- | buffer (`working`) accumulates diffused error and is read back
-- | before each pixel is quantized; a separate `output` buffer holds
-- | only the quantized values. No bounds-checking trickery beyond the
-- | direct `0 <= x' < width && 0 <= y' < height` check the mathematics
-- | itself calls for.
-- |
-- | Assumes `image` is rectangular and non-empty.
referenceDither
  :: forall a
   . Ring a
  => Scalable a
  => Kernel
  -> Quantize a
  -> Array (Array a)
  -> Array (Array a)
referenceDither kernel quantize image =
  unflatten width height (run (ditherFlat width height (flatten image)))
  where
    width :: Int
    width = case Array.head image of
      Nothing -> 0
      Just row -> Array.length row

    height :: Int
    height = Array.length image

    ditherFlat :: forall r. Int -> Int -> Array a -> ST r (Array a)
    ditherFlat w h flat = do
      working <- STArray.thaw flat
      output <- STArray.thaw flat  -- placeholder contents; every cell is overwritten below

      let
        indexOf :: Int -> Int -> Int
        indexOf x y = y * w + x

      forE_ 0 h \y ->
        forE_ 0 w \x -> do
          let idx = indexOf x y
          maybeCorrected <- STArray.peek idx working
          case maybeCorrected of
            Nothing -> pure unit  -- unreachable: idx is always in range by construction
            Just corrected -> do
              let
                quantized = runQuantize quantize { x, y } corrected
                err = corrected - quantized
              _ <- STArray.poke idx quantized output
              forKernel_ kernel \{ dx, dy, weight } -> do
                let
                  x' = x + dx
                  y' = y + dy
                when (x' >= 0 && x' < w && y' >= 0 && y' < h) do
                  maybeNeighbor <- STArray.peek (indexOf x' y') working
                  case maybeNeighbor of
                    Nothing -> pure unit  -- unreachable: bounds already checked
                    Just neighborVal -> do
                      _ <- STArray.poke (indexOf x' y') (neighborVal + scale weight err) working
                      pure unit

      STArray.freeze output

    -- Small local helpers to avoid pulling in a Traversable-based loop
    -- (kept explicit/imperative on purpose — clarity for a reference
    -- implementation matters more than idiom here).
    forE_ :: forall r. Int -> Int -> (Int -> ST r Unit) -> ST r Unit
    forE_ lo hi f = go lo
      where
        go i = when (i < hi) do
          f i
          go (i + 1)

    forKernel_ :: forall r. Kernel -> ({ dx :: Int, dy :: Int, weight :: Number } -> ST r Unit) -> ST r Unit
    forKernel_ k f = go 0
      where
        ks = offsets k
        n = Array.length ks
        go i = when (i < n) do
          case Array.index ks i of
            Nothing -> pure unit
            Just o -> f o
          go (i + 1)