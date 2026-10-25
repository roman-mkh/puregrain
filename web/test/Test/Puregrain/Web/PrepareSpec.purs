module Test.Puregrain.Web.PrepareSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Foldable (for_, sum)
import Data.Int (round, toNumber)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Class (liftEffect)
import Puregrain.Web.Prepare (backgroundFromHex, backgroundHex, backgroundShows, fitOnto, flatten, flattenChannel, hasTransparency, placementOn, screenToFit, white)
import Puregrain.Web.Settings (MachineName(..), Target(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

foreign import rgbaOf :: Array Int -> Effect Uint8ClampedArray
foreign import valuesOf :: Uint8ClampedArray -> Effect (Array Int)

type Size = { width :: Int, height :: Int }

-- | A picture's RGBA values from a function of the position.
pictureOf :: Size -> (Int -> Int -> { r :: Int, g :: Int, b :: Int, a :: Int }) -> Array Int
pictureOf size f = do
  y <- 0 .. (size.height - 1)
  x <- 0 .. (size.width - 1)
  let p = f x y
  [ p.r, p.g, p.b, p.a ]

-- | The fit worked out the plain way, independently of `Prepare.js`: for
-- | each screen pixel inside the placed picture, the sum over every
-- | picture pixel of its color times its overlap with the screen pixel,
-- | counted in the same whole-number units, divided by their total.
fitByHand :: Array Int -> Size -> Size -> { r :: Int, g :: Int, b :: Int } -> Array Int
fitByHand pixels picture screen bg = do
  y <- 0 .. (screen.height - 1)
  x <- 0 .. (screen.width - 1)
  let
    tx = x - p.left
    ty = y - p.top
  if tx < 0 || ty < 0 || tx >= p.width || ty >= p.height then [ bg.r, bg.g, bg.b, 255 ]
  else
    map (channel tx ty) [ 0, 1, 2 ] <> [ 255 ]
  where
  p = placementOn screen picture
  overlap n m t i = max 0 (min ((t + 1) * n) ((i + 1) * m) - max (t * n) (i * m))
  channel tx ty k =
    let
      s = sum do
        j <- 0 .. (picture.height - 1)
        i <- 0 .. (picture.width - 1)
        let w = overlap picture.width p.width tx i * overlap picture.height p.height ty j
        pure (toNumber (w * fromMaybe 0 (Array.index pixels ((j * picture.width + i) * 4 + k))))
    in
      round (s / toNumber (picture.width * picture.height))

spec :: Spec Unit
spec = describe "Puregrain.Web.Prepare" do
  describe "the background" do
    it "is written and read as six hex digits, as a color input gives them" do
      backgroundHex white `shouldEqual` "ffffff"
      backgroundHex { r: 42, g: 90, b: 200 } `shouldEqual` "2a5ac8"
      backgroundHex { r: 0, g: 5, b: 16 } `shouldEqual` "000510"
      backgroundFromHex "#2A5AC8" `shouldEqual` Just { r: 42, g: 90, b: 200 }
      backgroundFromHex "000510" `shouldEqual` Just { r: 0, g: 5, b: 16 }
      for_ [ "", "#12345", "#1234567", "zzzzzz", "#12 456" ] \s -> backgroundFromHex s `shouldEqual` Nothing

    it "shows under transparent parts, and around a fitted picture that doesn't fill the screen" do
      let screen = { width: 256, height: 192 }
      backgroundShows true Nothing `shouldEqual` true
      backgroundShows false Nothing `shouldEqual` false
      backgroundShows false (Just { screen, placement: placementOn screen { width: 100, height: 80 } }) `shouldEqual` true
      backgroundShows false (Just { screen, placement: placementOn screen { width: 6000, height: 4000 } }) `shouldEqual` false

  describe "flattening" do
    it "keeps an opaque color, gives the background where it's transparent, and mixes between" do
      flattenChannel 200 255 0 `shouldEqual` 200
      flattenChannel 200 0 37 `shouldEqual` 37
      flattenChannel 200 128 255 `shouldEqual` 227

    it "flattens whole pictures as flattenChannel does, for every value and alpha" do
      let all = pictureOf { width: 256, height: 256 } \x y -> { r: y, g: 255 - y, b: (y * 37) `mod` 256, a: x }
      pixels <- liftEffect (rgbaOf all)
      for_ [ white, { r: 0, g: 0, b: 0 }, { r: 42, g: 90, b: 200 } ] \bg -> do
        got <- liftEffect (valuesOf =<< flatten pixels bg)
        let
          want = Array.concat do
            i <- 0 .. (256 * 256 - 1)
            let v k = fromMaybe 0 (Array.index all (i * 4 + k))
            pure [ flattenChannel (v 0) (v 3) bg.r, flattenChannel (v 1) (v 3) bg.g, flattenChannel (v 2) (v 3) bg.b, 255 ]
        when (got /= want) (fail ("differs from flattenChannel onto " <> backgroundHex bg))

    it "finds transparency in any pixel's alpha" do
      opaque <- liftEffect (rgbaOf (pictureOf { width: 3, height: 2 } \_ _ -> { r: 1, g: 2, b: 3, a: 255 }))
      oneBelow <- liftEffect (rgbaOf (pictureOf { width: 3, height: 2 } \x y -> { r: 1, g: 2, b: 3, a: if x == 2 && y == 1 then 254 else 255 }))
      transparentOrNot <- liftEffect ((\a b -> [ a, b ]) <$> hasTransparency opaque <*> hasTransparency oneBelow)
      transparentOrNot `shouldEqual` [ false, true ]

  describe "the fit, by decision 22" do
    it "fits only to a machine's screen, when asked, and a picture of another size" do
      let size = { width: 640, height: 480 }
      screenToFit AnyScreen true size `shouldEqual` Nothing
      screenToFit (Machine ZxSpectrumScreen) false size `shouldEqual` Nothing
      screenToFit (Machine ZxSpectrumScreen) true { width: 256, height: 192 } `shouldEqual` Nothing
      screenToFit (Machine ZxSpectrumScreen) true size `shouldEqual` Just { width: 256, height: 192 }
      screenToFit (Machine C64HiresScreen) true size `shouldEqual` Just { width: 320, height: 200 }

    it "scales down, never up, to cover the screen, centered, as the roadmap's table says" do
      let screen = { width: 256, height: 192 }
      placementOn screen { width: 4000, height: 3000 } `shouldEqual` { width: 256, height: 192, left: 0, top: 0 }
      placementOn screen { width: 6000, height: 4000 } `shouldEqual` { width: 288, height: 192, left: -16, top: 0 }
      placementOn screen { width: 100, height: 80 } `shouldEqual` { width: 100, height: 80, left: 78, top: 56 }
      placementOn screen { width: 300, height: 100 } `shouldEqual` { width: 300, height: 100, left: -22, top: 46 }
      placementOn screen { width: 256, height: 192 } `shouldEqual` { width: 256, height: 192, left: 0, top: 0 }
      -- a tall picture: the width decides; an odd overflow crops one more row at the top
      placementOn screen { width: 1000, height: 5000 } `shouldEqual` { width: 256, height: 1280, left: 0, top: -544 }
      placementOn screen { width: 289, height: 192 } `shouldEqual` { width: 289, height: 192, left: -17, top: 0 }

    it "fits whole pictures as the plain sum of overlaps does: scaled, cropped, or on the background" do
      let
        cases =
          [ { picture: { width: 23, height: 17 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 40, height: 9 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 7, height: 5 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 30, height: 4 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 13, height: 29 }, screen: { width: 8, height: 5 } }
          ]
        bg = { r: 42, g: 90, b: 200 }
      for_ cases \c -> do
        let values = pictureOf c.picture \x y -> { r: (x * 37 + y * 11) `mod` 256, g: (x * y * 13) `mod` 256, b: (x + y * 7) `mod` 256, a: 255 }
        pixels <- liftEffect (rgbaOf values)
        got <- liftEffect (valuesOf =<< fitOnto pixels c.picture c.screen bg)
        when (got /= fitByHand values c.picture c.screen bg) (fail ("the fit differs for " <> show c))
