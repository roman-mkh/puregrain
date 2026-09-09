module Dither.Ffi where

import Data.List.Lazy as LL

import Dither.Kernel (Kernel)
import Dither.Image (ditherImage)

-- | FFI-удобная обёртка над ditherImage: принимает и возвращает обычные
-- | JS-массивы (Array (Array Number)), а не ленивые списки. Для PoC/CLI
-- | скрипта, где вся картинка и так уже целиком в памяти на входе —
-- | ленивость на этой границе не даёт выгоды, только совместимость
-- | с обычным JS-кодом на другой стороне.
ditherImageArray
  :: Kernel
  -> (Number -> Number)
  -> Array (Array Number)
  -> Array (Array Number)
ditherImageArray kernel quantize rows =
  LL.toUnfoldable (ditherImage kernel quantize (LL.fromFoldable rows))