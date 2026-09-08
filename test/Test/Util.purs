module Test.Util where

import Prelude

import Data.Array as Array
import Data.Foldable (and)
import Data.Ord (abs)
import Data.List.Lazy as LL

import Dither.State (RowLayer)

approxEqual :: Number -> Number -> Boolean
approxEqual a b = abs (a - b) < 0.0001

approxArrayEqual :: Array Number -> Array Number -> Boolean
approxArrayEqual xs ys =
  Array.length xs == Array.length ys
    && and (Array.zipWith approxEqual xs ys)

takeAsArray :: Int -> LL.List Number -> Array Number
takeAsArray n fifo = LL.toUnfoldable (LL.take n fifo)

takeLayersAsArray :: Int -> LL.List RowLayer -> Array RowLayer
takeLayersAsArray n dl = LL.toUnfoldable (LL.take n dl)