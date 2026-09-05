module Dither.Debug where

import Prelude

import Data.Array as Array
import Data.List.Lazy as LL
import Dither.State (DitherState, Fifo)

showFifoPreview :: Int -> LL.List Number -> String
showFifoPreview n fifo =
  let preview = LL.toUnfoldable (LL.take n fifo) :: Array Number
  in show preview <> " ..."

showStatePreview :: Int -> DitherState -> String
showStatePreview n state =
  "{ current: " <> showFifos state.current
    <> ", past: " <> showFifos state.past
    <> ", future: " <> showFifos state.future
    <> " }"
  where
    showFifos :: Array Fifo -> String
    showFifos fifos =
      "[" <> Array.intercalate ", " (map (showFifoPreview n) fifos) <> "]"