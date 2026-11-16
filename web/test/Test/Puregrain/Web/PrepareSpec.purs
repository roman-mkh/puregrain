module Test.Puregrain.Web.PrepareSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Foldable (for_, sum)
import Data.Int (round, toNumber)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Number (pow)
import Data.Ord (abs)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Console (log)
import Puregrain.Gamma (toLight)
import Puregrain.Web.Dither (gammaOf)
import Puregrain.Web.Prepare (LightTables, backgroundFromHex, backgroundHex, backgroundShows, byteOfLight, fitOnto, flatten, flattenChannel, flattenChannelIn, hasTransparency, lightTables, placementOn, screenToFit, white)
import Puregrain.Web.Settings (GammaName(..), MachineName(..), Target(..))
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

-- | The four curves' names, for the tests in light.
curveNames :: Array GammaName
curveNames = [ Gamma1p2, Gamma1p5, Gamma1p8, GammaSrgb ]

-- | A curve's tables; every curve but off has them.
tablesOf :: GammaName -> LightTables
tablesOf name = fromMaybe { light: [], cuts: [] } (lightTables name)

-- | The fit in light worked out the plain way, independently of
-- | `Prepare.js`: for each screen pixel inside the placed picture, the
-- | sum over every picture pixel of its light times its overlap, divided
-- | by the total; each mean with the byte `byteOfLight` gives it. Summed
-- | in another order than `Prepare.js`, so the last bits of a mean may
-- | differ: the test allows a different byte only where the mean lies
-- | within 10^-9 of a half-step.
fitInLightByHand :: LightTables -> Array Int -> Size -> Size -> { r :: Int, g :: Int, b :: Int } -> Array { byte :: Int, mean :: Maybe Number }
fitInLightByHand t pixels picture screen bg = do
  y <- 0 .. (screen.height - 1)
  x <- 0 .. (screen.width - 1)
  let
    tx = x - p.left
    ty = y - p.top
  if tx < 0 || ty < 0 || tx >= p.width || ty >= p.height then map (\v -> { byte: v, mean: Nothing }) [ bg.r, bg.g, bg.b, 255 ]
  else
    map (channel tx ty) [ 0, 1, 2 ] <> [ { byte: 255, mean: Nothing } ]
  where
  p = placementOn screen picture
  overlap n m t' i = max 0 (min ((t' + 1) * n) ((i + 1) * m) - max (t' * n) (i * m))
  lightAt i = fromMaybe 0.0 (Array.index t.light i)
  channel tx ty k =
    let
      s = sum do
        j <- 0 .. (picture.height - 1)
        i <- 0 .. (picture.width - 1)
        let w = overlap picture.width p.width tx i * overlap picture.height p.height ty j
        pure (toNumber w * lightAt (fromMaybe 0 (Array.index pixels ((j * picture.width + i) * 4 + k))))
      mean = s / toNumber (picture.width * picture.height)
    in
      { byte: byteOfLight t mean, mean: Just mean }

-- | sRGB's curve on the 0–255 scale, both ways, written with `pow` as the
-- | W3C's sample code has it: an independent reference for decision 6's
-- | examples (approximated by the standard, so used only where the result
-- | lies far from a half-step).
srgbToLight :: Number -> Number
srgbToLight v = let c = v / 255.0 in 255.0 * (if c <= 0.04045 then c / 12.92 else pow ((c + 0.055) / 1.055) 2.4)

srgbFromLight :: Number -> Number
srgbFromLight v = let l = v / 255.0 in 255.0 * (if l > 0.0031308 then 1.055 * pow l (1.0 / 2.4) - 0.055 else 12.92 * l)

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
        got <- liftEffect (valuesOf =<< flatten Nothing pixels bg)
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

  describe "in a curve's light (linear light's decision 6)" do
    it "has no tables for off" do
      (lightTables GammaOff == Nothing) `shouldEqual` true

    it "brings every byte back from its light, and goes up exactly at a half-step" do
      for_ curveNames \name -> do
        let
          t = tablesOf name
          gamma = gammaOf name
          wrong = Array.filter (\b -> byteOfLight t (toLight gamma (toNumber b)) /= b) (0 .. 255)
          atCuts = Array.filter (\b -> byteOfLight t (toLight gamma (toNumber b + 0.5)) /= b + 1) (0 .. 254)
          between = Array.filter (\b -> byteOfLight t ((toLight gamma (toNumber b) + toLight gamma (toNumber b + 0.5)) / 2.0) /= b) (0 .. 254)
        { name, wrong, atCuts, between } `shouldEqual` { name, wrong: [], atCuts: [], between: [] }
        { name, below: byteOfLight t (-1.0), above: byteOfLight t 300.0 } `shouldEqual` { name, below: 0, above: 255 }

    it "flattens to exactly the color where opaque and the background where transparent" do
      for_ curveNames \name -> do
        let
          t = lightTables name
          wrong = Array.filter (\c -> flattenChannelIn t c 255 37 /= c || flattenChannelIn t 200 0 c /= c) (0 .. 255)
        { name, wrong } `shouldEqual` { name, wrong: [] }

    it "flattens half-transparent black over white to sRGB's gray of half the light, 187 or 188" do
      let
        expected alpha = round (srgbFromLight (srgbToLight 0.0 * a + srgbToLight 255.0 * (1.0 - a)))
          where
          a = toNumber alpha / 255.0
      map (\alpha -> flattenChannelIn (lightTables GammaSrgb) 0 alpha 255) [ 127, 128 ] `shouldEqual` map expected [ 127, 128 ]
      map (\alpha -> flattenChannelIn (lightTables GammaSrgb) 0 alpha 255) [ 127, 128 ] `shouldEqual` [ 188, 187 ]
      map (\alpha -> flattenChannelIn Nothing 0 alpha 255) [ 127, 128 ] `shouldEqual` [ 128, 127 ]

    it "flattens whole pictures as flattenChannelIn does, for every value and alpha, under every curve" do
      let all = pictureOf { width: 256, height: 256 } \x y -> { r: y, g: 255 - y, b: (y * 37) `mod` 256, a: x }
      pixels <- liftEffect (rgbaOf all)
      for_ curveNames \name -> for_ [ white, { r: 0, g: 0, b: 0 }, { r: 42, g: 90, b: 200 } ] \bg -> do
        let t = lightTables name
        got <- liftEffect (valuesOf =<< flatten t pixels bg)
        let
          want = Array.concat do
            i <- 0 .. (256 * 256 - 1)
            let v k = fromMaybe 0 (Array.index all (i * 4 + k))
            pure [ flattenChannelIn t (v 0) (v 3) bg.r, flattenChannelIn t (v 1) (v 3) bg.g, flattenChannelIn t (v 2) (v 3) bg.b, 255 ]
        when (got /= want) (fail ("differs from flattenChannelIn onto " <> backgroundHex bg <> " under " <> show name))

    it "fits fine black and white lines, halved, to sRGB's gray of half the light, 188, not 128" do
      let lines = pictureOf { width: 8, height: 4 } \x _ -> let v = if x `mod` 2 == 0 then 0 else 255 in { r: v, g: v, b: v, a: 255 }
      pixels <- liftEffect (rgbaOf lines)
      inLight <- liftEffect (valuesOf =<< fitOnto (lightTables GammaSrgb) pixels { width: 8, height: 4 } { width: 4, height: 2 } white)
      stored <- liftEffect (valuesOf =<< fitOnto Nothing pixels { width: 8, height: 4 } { width: 4, height: 2 } white)
      Array.nub inLight `shouldEqual` [ 188, 255 ]
      Array.nub stored `shouldEqual` [ 128, 255 ]
      round (srgbFromLight ((srgbToLight 0.0 + srgbToLight 255.0) / 2.0)) `shouldEqual` 188

    it "fits whole pictures in light as the plain sum of overlaps does, under every curve" do
      let
        cases =
          [ { picture: { width: 23, height: 17 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 40, height: 9 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 7, height: 5 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 30, height: 4 }, screen: { width: 9, height: 7 } }
          , { picture: { width: 13, height: 29 }, screen: { width: 8, height: 5 } }
          ]
        bg = { r: 42, g: 90, b: 200 }
      for_ curveNames \name -> for_ cases \c -> do
        let
          t = tablesOf name
          values = pictureOf c.picture \x y -> { r: (x * 37 + y * 11) `mod` 256, g: (x * y * 13) `mod` 256, b: (x + y * 7) `mod` 256, a: 255 }
          nearCut m = Array.any (\cut -> abs (m - cut) < 1.0e-9) t.cuts
        pixels <- liftEffect (rgbaOf values)
        got <- liftEffect (valuesOf =<< fitOnto (Just t) pixels c.picture c.screen bg)
        let
          want = fitInLightByHand t values c.picture c.screen bg
          differ = Array.filter (\{ g, w } -> g /= w.byte) (Array.zipWith (\g w -> { g, w }) got want)
          allowed = Array.filter (\{ w } -> maybe false nearCut w.mean) differ
        when (Array.length got /= Array.length want || Array.length differ /= Array.length allowed)
          (fail ("the fit in light differs for " <> show c <> " under " <> show name <> ": " <> show (Array.length differ) <> " values"))
        -- A byte that differs only by a mean at a half-step is allowed, and
        -- reported (none expected).
        when (Array.length allowed > 0)
          (liftEffect (log ("  note: " <> show (Array.length allowed) <> " means at a half-step for " <> show c <> " under " <> show name)))

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
        got <- liftEffect (valuesOf =<< fitOnto Nothing pixels c.picture c.screen bg)
        when (got /= fitByHand values c.picture c.screen bg) (fail ("the fit differs for " <> show c))
