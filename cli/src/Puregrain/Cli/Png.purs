-- | PNG input/output, via a small JS foreign module (pngjs).
-- | Pixels cross the boundary as plain records, not as the library's
-- | `RGB` newtype: the JS side shouldn't need to know how PureScript
-- | represents a newtype at runtime. Callers convert with `coerce`.
module Puregrain.Cli.Png
  ( Rgb
  , readRgbRows
  , writeGrayRows
  , writeRgbRows
  ) where

import Prelude

import Effect (Effect)

-- | A pixel as the JS side sees it: 0–255 per channel.
type Rgb = { r :: Number, g :: Number, b :: Number }

-- | Reads any PNG pngjs can decode as rows of RGB, ignoring alpha. Throws
-- | an Error with a readable message if the file can't be read or decoded.
foreign import readRgbRows :: String -> Effect (Array (Array Rgb))

-- | Writes an 8-bit grayscale PNG. Values are rounded and clamped to [0,255].
foreign import writeGrayRows :: String -> Array (Array Number) -> Effect Unit

-- | Writes an 8-bit RGB PNG, no alpha. Values are rounded and clamped to [0,255].
foreign import writeRgbRows :: String -> Array (Array Rgb) -> Effect Unit
