-- | The screen the page is shown on. (`web-html` doesn't bind
-- | `devicePixelRatio`.)
module Puregrain.Web.Screen (pixelRatio) where

import Effect (Effect)

-- | Screen pixels per CSS pixel, `window.devicePixelRatio`: 1 on most
-- | desktop monitors, 2 on high-density screens, 1.25 or 1.5 on many
-- | laptops. The browser's own zoom changes it.
foreign import pixelRatio :: Effect Number
