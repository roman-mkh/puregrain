-- | The quick start from the main README: a small gray gradient, made in
-- | code, and the same gradient dithered to black and white with
-- | Floyd-Steinberg, both printed as text. Run it from the repository root:
-- |
-- |     npx spago run -p puregrain-examples -m Puregrain.Examples.QuickStart
module Puregrain.Examples.QuickStart
  ( gradient
  , main
  , render
  , shades
  ) where

import Prelude

import Data.Array as Array
import Data.Int (round, toNumber)
import Data.Maybe (fromMaybe)
import Data.String (joinWith)
import Effect (Effect)
import Effect.Console (log)
import Puregrain as P

-- | A small gray image: 8 rows of 32 pixels, from black (0.0) on the left
-- | to white (255.0) on the right.
gradient :: Array (Array Number)
gradient = Array.replicate 8 (map (\x -> toNumber x * 255.0 / 31.0) (Array.range 0 31))

main :: Effect Unit
main = do
  log "The original gradient (shown with 5 shades):"
  log (render gradient)
  log ""
  log "Dithered to black and white with Floyd-Steinberg:"
  log (render (P.ditherImage P.floydSteinberg (P.threshold 128.0) gradient))

-- | Shows an image as text, one line per row: each pixel becomes the
-- | entry of `shades` nearest to its gray value (0.0 to 255.0).
render :: Array (Array Number) -> String
render image = joinWith "\n" (map (joinWith "" <<< map shade) image)
  where
  darkest = 0
  lightest = Array.length shades - 1
  shade value =
    let i = clamp darkest lightest (round (value / 255.0 * toNumber lightest))
    in fromMaybe "" (Array.index shades i)

-- | The characters for 5 shades of gray, from black to white, 2 per pixel
-- | so the pixels come out square. Made for a dark background, where █
-- | shows as white. On a light background, reverse the list:
-- | [ "██", "▓▓", "▒▒", "░░", "  " ]
shades :: Array String
shades = [ "  ", "░░", "▒▒", "▓▓", "██" ]
