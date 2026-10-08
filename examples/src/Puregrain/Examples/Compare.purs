-- | The gradient from the quick start, dithered to black and white in three
-- | ways, to compare them. Run it from the repository root:
-- |
-- |     npx spago run -p puregrain-examples -m Puregrain.Examples.Compare
module Puregrain.Examples.Compare
  ( main
  ) where

import Prelude

import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Console (log)
import Puregrain as P
import Puregrain.Examples.QuickStart (gradient, render)

main :: Effect Unit
main = do
  picture "The original gradient (shown with 5 shades):"
    gradient

  picture "No diffusion (a threshold at 128): the gradient becomes a hard edge."
    (P.ditherImage P.noDiffusion (P.threshold 128.0) gradient)

  picture "Floyd-Steinberg: the rounding error spreads, so the dots follow the gray."
    (P.ditherImage P.floydSteinberg (P.threshold 128.0) gradient)

  -- `bayer` takes the side of the map, which must be a power of 2, so it
  -- returns a `Maybe`.
  case P.bayer 4 of
    Just bayer4 ->
      picture "Bayer 4×4 (ordered): a fixed pattern of thresholds, a regular grid of dots."
        (P.ditherImage P.noDiffusion (P.ordered bayer4 (P.evenRamp 2)) gradient)
    Nothing ->
      log "No Bayer map of side 4."

  where
  picture title image = do
    log title
    log (render image)
    log ""
