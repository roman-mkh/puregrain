module Dither.State where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.List.Lazy (List)
import Data.List.Lazy as LL
import Data.Tuple (Tuple(..))

import Dither.Kernel (CompiledKernel)
import Dither.Kernel as K

type Fifo = List Number
type RowLayer = Array Fifo

data SeededFifo = Constant Number | Real Fifo
type SeededLayer = Array SeededFifo
type DelayLine = List SeededLayer

type DitherState = { delayLines :: Array DelayLine }

type RowState =
  { current  :: RowLayer
  , matured  :: Array RowLayer
  , building :: Array RowLayer
  }

freshLayer :: Array K.Offset -> RowLayer
freshLayer = map (\o -> LL.replicate (K.paddingFor o) 0.0)

placeholderLayer :: Array K.Offset -> SeededLayer
placeholderLayer offsets = map (const (Constant 0.0)) offsets

initState :: CompiledKernel -> DitherState
initState compiled =
  { delayLines: map initDelayLineFor (Array.zip (1 .. compiled.maxDepth) compiled.futureLayers) }
  where
    initDelayLineFor :: Tuple Int (Array K.Offset) -> DelayLine
    initDelayLineFor (Tuple dy offsets) =
      LL.fromFoldable (Array.replicate dy (placeholderLayer offsets))