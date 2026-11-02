-- | Preparing a picture before it's dithered (decisions 22 and 27 in
-- | web/ROADMAP.md): its transparent parts put onto a background color,
-- | and, for a machine's screen, the picture fitted to the screen. Our own
-- | code, not the browser's compositing or scaling, so the result is the
-- | same in every browser, and can become the CLI's too (with the library,
-- | later). The loops over a whole picture are in `Prepare.js`, for speed;
-- | specs pin them to the rules here.
module Puregrain.Web.Prepare
  ( Background
  , white
  , backgroundHex
  , backgroundFromHex
  , flattenChannel
  , Placement
  , screenToFit
  , placementOn
  , isScaledDown
  , isCropped
  , leavesBackground
  , backgroundShows
  , hasTransparency
  , flatten
  , fitOnto
  ) where

import Prelude

import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Int (fromStringAs, hexadecimal, round, toNumber, toStringAs)
import Data.Maybe (Maybe(..), maybe)
import Data.String.CodeUnits as CodeUnits
import Data.String.Common (joinWith, toLower)
import Data.Traversable (traverse)
import Effect (Effect)
import Puregrain.Web.Settings (Target(..), screenSizeOf)

-- | A background color, each channel 0 to 255.
type Background = { r :: Int, g :: Int, b :: Int }

white :: Background
white = { r: 255, g: 255, b: 255 }

-- | As six hex digits, `ffffff` (a color input's value without its `#`,
-- | and the part of a download's name).
backgroundHex :: Background -> String
backgroundHex c = joinWith "" (map two [ c.r, c.g, c.b ])
  where
  two v = let s = toStringAs hexadecimal v in if v < 16 then "0" <> s else s

-- | From `#rrggbb` or `rrggbb`, as a color input gives it.
backgroundFromHex :: String -> Maybe Background
backgroundFromHex s = do
  let digits = toLower (if CodeUnits.take 1 s == "#" then CodeUnits.drop 1 s else s)
  if CodeUnits.length digits /= 6 then Nothing
  else do
    channels <- traverse (\i -> fromStringAs hexadecimal (CodeUnits.slice i (i + 2) digits)) [ 0, 2, 4 ]
    case channels of
      [ r, g, b ] -> Just { r, g, b }
      _ -> Nothing

-- | One channel of a pixel put onto the background: the color where the
-- | pixel is opaque, the background where it's transparent, mixed in
-- | between: color × alpha + background × (1 − alpha), rounded
-- | (`Math.round`, as everywhere in puregrain-web).
-- |
-- | ```purescript
-- | flattenChannel 200 128 255 == 227
-- | ```
flattenChannel :: Int -> Int -> Int -> Int
flattenChannel color alpha background =
  round (toNumber color * a + toNumber background * (1.0 - a))
  where
  a = toNumber alpha / 255.0

-- | The screen to fit a picture to: a machine's, when fitting is asked
-- | for and the picture isn't the screen's size (decision 22). Only a
-- | machine has a screen.
screenToFit :: Target -> Boolean -> { width :: Int, height :: Int } -> Maybe { width :: Int, height :: Int }
screenToFit target fit picture = case target of
  Machine machine | fit && screenSizeOf machine /= picture -> Just (screenSizeOf machine)
  _ -> Nothing

-- | Where a picture goes on a screen: its size after scaling, and its
-- | left and top edges on the screen, negative where it's cropped.
type Placement = { width :: Int, height :: Int, left :: Int, top :: Int }

-- | The rule of decision 22: scaled down, never up, so that it covers the
-- | screen as far as it can; centered, `left` and `top` rounded down;
-- | cropped where it overflows; the background where it doesn't reach.
-- | Of a scaled picture, one side fills the screen exactly and the other
-- | is rounded to the nearest pixel.
-- |
-- | ```purescript
-- | placementOn { width: 256, height: 192 } { width: 6000, height: 4000 }
-- |   == { width: 288, height: 192, left: -16, top: 0 }
-- | ```
placementOn :: { width :: Int, height :: Int } -> { width :: Int, height :: Int } -> Placement
placementOn screen picture = { width, height, left: (screen.width - width) `div` 2, top: (screen.height - height) `div` 2 }
  where
  -- Covering the screen needs no enlarging when one side already reaches.
  fits = screen.width >= picture.width || screen.height >= picture.height
  -- The side whose ratio is larger decides: the other overflows.
  widthDecides = screen.width * picture.height >= screen.height * picture.width
  { width, height } =
    if fits then { width: picture.width, height: picture.height }
    else if widthDecides then { width: screen.width, height: roundedRatio (picture.height * screen.width) picture.width }
    else { width: roundedRatio (picture.width * screen.height) picture.height, height: screen.height }

-- | n ÷ d rounded to the nearest whole number, halves up, for positive n
-- | and d. (A pattern binding in a `where` can't use a later binding.)
roundedRatio :: Int -> Int -> Int
roundedRatio n d = (2 * n + d) `div` (2 * d)

isScaledDown :: { width :: Int, height :: Int } -> Placement -> Boolean
isScaledDown picture p = p.width < picture.width

isCropped :: { width :: Int, height :: Int } -> Placement -> Boolean
isCropped screen p = p.width > screen.width || p.height > screen.height

-- | Whether the background shows around the picture on the screen.
leavesBackground :: { width :: Int, height :: Int } -> Placement -> Boolean
leavesBackground screen p = p.width < screen.width || p.height < screen.height

-- | Whether the background shows in the result (decision 27): under a
-- | picture's transparent parts, or around a fitted picture that doesn't
-- | fill the screen.
backgroundShows :: Boolean -> Maybe { screen :: { width :: Int, height :: Int }, placement :: Placement } -> Boolean
backgroundShows transparent fitted = transparent || maybe false (\f -> leavesBackground f.screen f.placement) fitted

-- | Whether any pixel of the RGBA bytes isn't fully opaque.
foreign import hasTransparency :: Uint8ClampedArray -> Effect Boolean

foreign import flattenImpl :: Uint8ClampedArray -> Int -> Int -> Int -> Effect Uint8ClampedArray

-- | The RGBA bytes put onto the background, by `flattenChannel`: new
-- | bytes, every pixel opaque.
flatten :: Uint8ClampedArray -> Background -> Effect Uint8ClampedArray
flatten pixels c = flattenImpl pixels c.r c.g c.b

foreign import fitImpl
  :: Uint8ClampedArray -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Int -> Effect Uint8ClampedArray

-- | The opaque picture (`picture`'s size) fitted to the screen as
-- | `placementOn` places it: new bytes of the screen's size, the
-- | background where the picture doesn't reach. Scaled down by area
-- | averaging: each screen pixel takes the mean of the picture's pixels it
-- | covers, weighted by how much of each it covers. The weights are whole
-- | numbers (the overlaps, counted in a fine enough unit), so every sum is
-- | exact and the result doesn't depend on the order of adding; the mean
-- | is rounded with `Math.round`.
fitOnto
  :: Uint8ClampedArray
  -> { width :: Int, height :: Int }
  -> { width :: Int, height :: Int }
  -> Background
  -> Effect Uint8ClampedArray
fitOnto pixels picture screen c =
  fitImpl pixels picture.width picture.height screen.width screen.height p.width p.height p.left p.top c.r c.g c.b
  where
  p = placementOn screen picture
