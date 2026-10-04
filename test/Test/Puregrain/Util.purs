module Test.Puregrain.Util where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Either (Either(..))
import Data.Foldable (and)
import Data.Maybe (Maybe(..))
import Data.Ord (abs)
import Data.List.Lazy as LL
import Partial.Unsafe (unsafePartial)

import Puregrain.Dither (ditherImage)
import Puregrain.Kernel (Kernel)
import Puregrain.Ordered (ThresholdMap, bayer, compileThresholdMap)
import Puregrain.Pixel (class Scalable, RGB(..))
import Puregrain.Quantize (Quantize, runQuantize)
import Puregrain.Internal.State (RowLayer)

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

-- | The six channel values the web-safe cube is built from, written out
-- | independently of `websafe216` (tests check the palette against it).
websafeSteps :: NonEmptyArray Number
websafeSteps = NEA.cons' 0.0 [ 51.0, 102.0, 153.0, 204.0, 255.0 ]

-- | Runs a quantizer at position (0, 0). Only meaningful for position-
-- | blind quantizers (`threshold`, `nearestLevel`, `nearestColor`, …),
-- | which give the same answer everywhere — PixelSpec checks that they do.
runAtOrigin :: forall a. Quantize a -> a -> a
runAtOrigin q = runQuantize q { x: 0, y: 0 }

-- | A neutral (gray) RGB pixel: the same value in every channel.
neutral :: Number -> RGB
neutral v = RGB { r: v, g: v, b: v }

-- | How many pixels of an RGB image are not neutral. A count rather than
-- | a Boolean, so a failing property reports how many pixels broke.
nonNeutralCount :: Array (Array RGB) -> Int
nonNeutralCount = Array.length <<< Array.filter (not <<< isNeutral) <<< Array.concat
  where
  isNeutral (RGB p) = p.r == p.g && p.g == p.b

-- | The n × n Bayer map, for tests that pass a valid side. Crashes
-- | otherwise: `bayer` itself returns `Nothing` there, and
-- | `Test.Puregrain.OrderedSpec` checks that it does.
bayerMap :: Int -> ThresholdMap
bayerMap n = unsafePartial case bayer n of
  Just m -> m

-- | A custom map from ranks that tests know are valid. Crashes
-- | otherwise; `Test.Puregrain.OrderedSpec` checks the rejections.
compiledMap :: Array (Array Int) -> ThresholdMap
compiledMap ranks = unsafePartial case compileThresholdMap ranks of
  Right m -> m
