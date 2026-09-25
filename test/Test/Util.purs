module Test.Util where

import Prelude

import Data.Array as Array
import Data.Foldable (and)
import Data.Ord (abs)
import Data.List.Lazy as LL

import Dither.Image (ditherImage)
import Dither.Kernel (Kernel)
import Dither.Pixel (class Scalable, Quantize, RGB(..))
import Dither.State (RowLayer)

approxEqual :: Number -> Number -> Boolean
approxEqual a b = abs (a - b) < 0.0001

approxArrayEqual :: Array Number -> Array Number -> Boolean
approxArrayEqual xs ys =
  Array.length xs == Array.length ys
    && and (Array.zipWith approxEqual xs ys)

takeAsArray :: Int -> LL.List Number -> Array Number
takeAsArray n fifo = LL.toUnfoldable (LL.take n fifo)

takeLayersAsArray :: forall f a. Int -> LL.List (RowLayer f a) -> Array (RowLayer f a)
takeLayersAsArray n dl = LL.toUnfoldable (LL.take n dl)

-- | Runs the public top-level `ditherImage` on an in-memory image.
-- | Polymorphic in the pixel type, so the same helper dithers a
-- | grayscale image and an RGB one; `LL.toUnfoldable` forces the whole
-- | lazy result.
dither :: forall a. Ring a => Scalable a => Kernel -> Quantize a -> Array (Array a) -> Array (Array a)
dither kernel quantize image =
  LL.toUnfoldable (ditherImage kernel quantize (LL.fromFoldable image))

-- | A neutral (gray) RGB pixel: the same value in every channel.
neutral :: Number -> RGB
neutral v = RGB { r: v, g: v, b: v }

-- | How many pixels of an RGB image are not neutral. A count rather than
-- | a Boolean, so a failing property reports how many pixels broke.
nonNeutralCount :: Array (Array RGB) -> Int
nonNeutralCount = Array.length <<< Array.filter (not <<< isNeutral) <<< Array.concat
  where
  isNeutral (RGB p) = p.r == p.g && p.g == p.b
