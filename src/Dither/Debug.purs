module Dither.Debug where

import Prelude

import Data.Array as Array
import Data.Int (floor, toNumber)
import Data.List.Lazy as LL
import Data.Maybe (Maybe(..))
import Data.String as String
import Data.String.CodePoints as SCP
import Dither.State (DelayLine, DitherState, Fifo, RowLayer, RowState)

showFifoPreview :: Int -> Fifo -> String
showFifoPreview n fifo =
  let preview = LL.toUnfoldable (LL.take n fifo) :: Array Number
  in show preview <> " ..."

showRowLayerPreview :: Int -> RowLayer -> String
showRowLayerPreview n layer =
  "[" <> Array.intercalate ", " (map (showFifoPreview n) layer) <> "]"

showDelayLinePreview :: Int -> Int -> DelayLine -> String
showDelayLinePreview m n delayLine =
  let layers = LL.toUnfoldable (LL.take m delayLine) :: Array RowLayer
  in "[" <> Array.intercalate ", " (map (showRowLayerPreview n) layers) <> "]"

showStatePreview :: Int -> Int -> DitherState -> String
showStatePreview m n state =
  "{ delayLines: [" <> Array.intercalate ", " (map (showDelayLinePreview m n) state.delayLines) <> "] }"

-- | Показывает превью RowState (внутристрочное состояние одного пикселя):
-- | current, matured и building — каждый как список RowLayer-превью
-- | (по n значений на FIFO внутри каждого слоя).
showRowStatePreview :: Int -> RowState -> String
showRowStatePreview n rowState =
  "{ current: " <> showRowLayerPreview n rowState.current
    <> ", matured: [" <> showLayers rowState.matured <> "]"
    <> ", building: [" <> showLayers rowState.building <> "]"
    <> " }"
  where
    showLayers :: Array RowLayer -> String
    showLayers = Array.intercalate ", " <<< map (showRowLayerPreview n)

-- | Показывает готовый результат dithering (Array строк, значения 0/255)
-- | как ASCII-art: 0.0 -> '.', иначе -> '#'.
showImageAscii :: LL.List (Array Number) -> String
showImageAscii rows =
  Array.intercalate "\n" (map showRow (LL.toUnfoldable rows :: Array (Array Number)))
  where
    showRow :: Array Number -> String
    showRow row = String.joinWith "" (map showPixel row)

    showPixel :: Number -> String
    showPixel p = if p == 0.0 then "." else "#"


-- | Рампа плотности символов, от самого светлого (пробел) до самого
-- | тёмного (@). Используется для ASCII-визуализации произвольных
-- | grayscale-значений (не только бинарного 0/255 результата dithering).
densityRamp :: String
densityRamp = " .:-=+*#%@"

-- | Отображает значение яркости 0-255 на символ рампы плотности.
brightnessToChar :: Number -> String
brightnessToChar brightness =
  let
    clamped = clamp 0.0 255.0 brightness
    rampLength = SCP.length densityRamp
    index = floor ((255.0 - clamped) / 255.0 * toNumber (rampLength - 1))
  in
    case SCP.codePointAt index densityRamp of
      Just cp -> SCP.singleton cp
      Nothing -> "?"

-- | Показывает произвольное grayscale-изображение (значения 0-255,
-- | ДО квантования) как ASCII-art через плотностную рампу.
showGrayscaleAscii :: LL.List (Array Number) -> String
showGrayscaleAscii rows =
  Array.intercalate "\n" (map showRow (LL.toUnfoldable rows :: Array (Array Number)))
  where
    showRow :: Array Number -> String
    showRow row = String.joinWith "" (map brightnessToChar row)    