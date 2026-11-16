-- The quick start, for Try PureScript (https://try.purescript.org), which
-- has puregrain among its packages. Open it there with
--
--   https://try.purescript.org/?github=roman-mkh/puregrain/master/examples/try/TryQuickStart.purs
--
-- A copy of examples/src/Puregrain/Examples/QuickStart.purs, with four
-- differences: the module is Main, which Try PureScript runs; main's
-- output goes onto the page through Try PureScript's own module,
-- TryPureScript, which exists only there; the shades are reversed, for
-- the page's light background; and a comment invites other kernels.
-- TryPureScript is also why this file isn't in the examples package's
-- src/ folder: spago compiles only src/, so our build never sees it. When
-- QuickStart.purs changes, update this copy too.
module Main where

import Prelude

import Data.Array as Array
import Data.Int (round, toNumber)
import Data.Maybe (fromMaybe)
import Data.String (joinWith)
import Effect (Effect)
import Effect.Console (log)
import Puregrain as P
import TryPureScript as Try

-- A small gray image: 8 rows of 32 pixels, from black (0.0) on the left
-- to white (255.0) on the right.
gradient :: Array (Array Number)
gradient = Array.replicate 8 (map (\x -> toNumber x * 255.0 / 31.0) (Array.range 0 31))

main :: Effect Unit
main = Try.render =<< Try.withConsole do
  log "The original gradient (shown with 5 shades):"
  log (render gradient)
  log ""
  log "Dithered to black and white with Floyd-Steinberg:"
  -- Try other kernels here: P.atkinson, P.jarvisJudiceNinke, P.stucki,
  -- P.sierraLite, or P.noDiffusion for none; or another threshold, such
  -- as P.threshold 96.0, and compare.
  log (render (P.ditherImage P.floydSteinberg (P.threshold 128.0) gradient))

-- Shows an image as text, one line per row: each pixel becomes the entry
-- of `shades` nearest to its gray value (0.0 to 255.0).
render :: Array (Array Number) -> String
render image = joinWith "\n" (map (joinWith "" <<< map shade) image)
  where
  darkest = 0
  lightest = Array.length shades - 1
  shade value =
    let i = clamp darkest lightest (round (value / 255.0 * toNumber lightest))
    in fromMaybe "" (Array.index shades i)

-- The characters for 5 shades of gray, from black to white, 2 per pixel
-- so the pixels come out square. Made for a light background, where █
-- shows as black. On a dark background, reverse the list:
-- [ "  ", "░░", "▒▒", "▓▓", "██" ]
shades :: Array String
shades = [ "██", "▓▓", "▒▒", "░░", "  " ]
