-- | Showing a picture at whole-number zoom: each picture pixel covers
-- | exactly `zoom` × `zoom` screen pixels, whatever the screen's pixel
-- | density, so dither patterns stay sharp. At any other scale the browser
-- | blurs them or forms moiré.
module Puregrain.Web.Zoom (zooms, cssSize) where

import Prelude

import Data.Int (toNumber)

-- | The zoom levels offered, in screen pixels per picture pixel.
zooms :: Array Int
zooms = [ 1, 2, 3, 4 ]

-- | The picture's size on the page in CSS pixels, at a zoom, on a screen
-- | with this pixel ratio. The ratio is `window.devicePixelRatio`, screen
-- | pixels per CSS pixel: 1 on most desktop monitors, 2 on high-density
-- | screens, 1.25 or 1.5 on many laptops, and changed by the browser's
-- | own zoom.
cssSize :: Number -> Int -> { width :: Int, height :: Int } -> { width :: Number, height :: Number }
cssSize ratio zoom size =
  { width: toNumber (size.width * zoom) / ratio
  , height: toNumber (size.height * zoom) / ratio
  }
