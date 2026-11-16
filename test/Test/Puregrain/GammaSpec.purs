module Test.Puregrain.GammaSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Foldable (and, for_)
import Data.Int (toNumber)
import Data.Number (pow, round)
import Data.Ord (abs)
import Test.QuickCheck ((<?>), (===))
import Test.QuickCheck.Gen (Gen, choose, chooseInt)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Gamma (Gamma, fromLight, gamma1p2, gamma1p5, gamma1p8, gammaOff, gammaSrgb, toGray, toLight)
import Puregrain.Internal.Gamma (fromLightFormula, lightTable, toLightFormula, toLightValue)
import Puregrain.Pixel (RGB(..), RGBA(..))
import Test.Puregrain.Arbitrary (TestRGB(..), genByteRGB)

bytes :: Array Number
bytes = map toNumber (0 .. 255)

-- | The four computed curves, each with an independent reference written
-- | with `pow` (approximated by the standard, so good only for comparing
-- | within a tolerance, never for the library itself).
curves :: Array { name :: String, gamma :: Gamma, to :: Number -> Number, back :: Number -> Number }
curves =
  [ power "1.2" gamma1p2 1.2
  , power "1.5" gamma1p5 1.5
  , power "1.8" gamma1p8 1.8
  , { name: "srgb", gamma: gammaSrgb, to: on255 srgbTo, back: on255 srgbBack }
  ]
  where
  power name gamma g = { name, gamma, to: on255 (\x -> pow x g), back: on255 (\l -> pow l (1.0 / g)) }
  on255 f v = 255.0 * f (v / 255.0)
  -- the W3C's sample code, CSS Color 4
  srgbTo c = if c <= 0.04045 then c / 12.92 else pow ((c + 0.055) / 1.055) 2.4
  srgbBack l = if l > 0.0031308 then 1.055 * pow l (1.0 / 2.4) - 0.055 else 12.92 * l

closeTo :: Number -> Number -> Boolean
closeTo expected actual = abs (actual - expected) <= 1.0e-12 * abs expected

-- | A value anywhere on the scale, mostly not a whole number.
genValue :: Gen Number
genValue = choose 0.01 255.0

-- | Luma as the CLI and the web UI compute it today, written out here:
-- | a neutral color its own value, any other Rec. 601 weights on the
-- | stored values.
luma :: RGB -> Number
luma (RGB p) = if p.r == p.g && p.g == p.b then p.r else 0.299 * p.r + 0.587 * p.g + 0.114 * p.b

allGammas :: Array Gamma
allGammas = [ gammaOff, gamma1p2, gamma1p5, gamma1p8, gammaSrgb ]

spec :: Spec Unit
spec = describe "Puregrain.Gamma" do

  describe "gammaOff" do
    it "is the identity, bit for bit, both ways" do
      map (toLight gammaOff) bytes `shouldEqual` bytes
      map (fromLight gammaOff) bytes `shouldEqual` bytes
      quickCheck do
        v <- choose (-300.0) 300.0
        pure (toLight gammaOff v == v && fromLight gammaOff v == v <?> ("changed " <> show v))

  for_ curves \c -> describe c.name do

    it "keeps 0 and 255 exactly, both ways" do
      map (toLight c.gamma) [ 0.0, 255.0 ] `shouldEqual` [ 0.0, 255.0 ]
      map (fromLight c.gamma) [ 0.0, 255.0 ] `shouldEqual` [ 0.0, 255.0 ]

    it "brings every byte back exactly from its light" do
      map (fromLight c.gamma <<< toLight c.gamma) bytes `shouldEqual` bytes

    it "rises strictly over the bytes and the halves between them" do
      let
        steps = map (\i -> toNumber i / 2.0) (0 .. 510)
        lights = map (toLight c.gamma) steps
      and (Array.zipWith (<) lights (Array.drop 1 lights)) `shouldEqual` true

    it "has a table that holds the formula's results" do
      lightTable c.gamma `shouldEqual` map (toLightFormula c.gamma) bytes
      map (toLightValue c.gamma) bytes `shouldEqual` lightTable c.gamma

    it "matches the curve's definition, within 10^-12" do
      quickCheck do
        v <- genValue
        let light = toLight c.gamma v
        pure (closeTo (c.to v) light <?> ("to light: " <> show v <> " gave " <> show light <> ", not " <> show (c.to v)))
      quickCheck do
        l <- genValue
        let stored = fromLight c.gamma l
        pure (closeTo (c.back l) stored <?> ("back: " <> show l <> " gave " <> show stored <> ", not " <> show (c.back l)))

    it "mirrors negative values" do
      quickCheck do
        v <- genValue
        pure (toLight c.gamma (negate v) === negate (toLight c.gamma v))
      quickCheck do
        l <- genValue
        pure (fromLight c.gamma (negate l) === negate (fromLight c.gamma l))

    it "takes the formula back for values that aren't a byte's light" do
      quickCheck do
        l <- genValue
        let isEntry = Array.elem l (lightTable c.gamma)
        pure ((isEntry || fromLight c.gamma l == fromLightFormula c.gamma l) <?> ("not the formula at " <> show l))

  describe "gammaSrgb" do
    it "gives gray 128 21.586% of white's light" do
      (toLight gammaSrgb 128.0 / 255.0) `shouldSatisfy` \y -> abs (y - 0.2158605) < 1.0e-7

  describe "the pixel types" do
    it "converts each of RGB's channels" do
      toLight gammaSrgb (RGB { r: 128.0, g: 64.0, b: 255.0 })
        `shouldEqual` RGB { r: toLight gammaSrgb 128.0, g: toLight gammaSrgb 64.0, b: 255.0 }

    it "keeps RGBA's alpha" do
      let
        RGBA p = toLight gamma1p5 (RGBA { r: 10.0, g: 20.0, b: 30.0, a: 128.0 })
        RGBA q = fromLight gamma1p5 (RGBA { r: 10.0, g: 20.0, b: 30.0, a: 128.0 })
      [ p.r, p.g, p.b, p.a ] `shouldEqual` [ toLight gamma1p5 10.0, toLight gamma1p5 20.0, toLight gamma1p5 30.0, 128.0 ]
      [ q.r, q.g, q.b, q.a ] `shouldEqual` [ fromLight gamma1p5 10.0, fromLight gamma1p5 20.0, fromLight gamma1p5 30.0, 128.0 ]

  describe "toGray" do
    it "with gammaOff, is luma on the stored values, as the CLI and the web UI have it" do
      quickCheck \(TestRGB color) -> toGray gammaOff color === luma color

    it "gives a neutral color exactly its own value, under every gamma" do
      for_ allGammas \gamma ->
        Array.filter (\v -> toGray gamma (RGB { r: v, g: v, b: v }) /= v) bytes `shouldEqual` []
      quickCheck \v -> and (map (\gamma -> toGray gamma (RGB { r: v, g: v, b: v }) == v) allGammas)

    it "never gives a darker gray when a channel rises, under every gamma" do
      for_ allGammas \gamma -> quickCheck do
        color@(RGB p) <- genByteRGB
        channel <- chooseInt 0 2
        rise <- toNumber <$> chooseInt 1 255
        let
          up v = min 255.0 (v + rise)
          brighter = case channel of
            0 -> RGB p { r = up p.r }
            1 -> RGB p { g = up p.g }
            _ -> RGB p { b = up p.b }
        pure ((toGray gamma brighter >= toGray gamma color) <?> ("darker: " <> show brighter <> " from " <> show color))

    for_ curves \c -> describe c.name do
      it "gives the gray whose light is the color's, by the curve's definition, within 10^-12" do
        quickCheck do
          RGB p <- genByteRGB
          let
            expected = 0.2126 * c.to p.r + 0.7152 * c.to p.g + 0.0722 * c.to p.b
            actual = c.to (toGray c.gamma (RGB p))
          pure ((abs (actual - expected) <= 1.0e-12 * max 1.0 expected) <?> ("light " <> show actual <> ", not " <> show expected))

      it "gives a gray that the dithering takes back to the color's light, within 10^-14 of it" do
        quickCheck do
          RGB p <- genByteRGB
          let
            light = 0.2126 * toLight c.gamma p.r + 0.7152 * toLight c.gamma p.g + 0.0722 * toLight c.gamma p.b
            again = toLight c.gamma (toGray c.gamma (RGB p))
          pure ((abs (again - light) <= 1.0e-14 * light) <?> ("light " <> show again <> ", not " <> show light))

    -- The table of linear light's decision 4 (CLAUDE.md; the spec in git
    -- history), measured independently: red, green, blue, magenta, skin,
    -- sky.
    it "gives decision 4's grays: with gammaOff luma's, with gammaSrgb lighter saturated colors" do
      let
        colors =
          [ RGB { r: 255.0, g: 0.0, b: 0.0 }
          , RGB { r: 0.0, g: 255.0, b: 0.0 }
          , RGB { r: 0.0, g: 0.0, b: 255.0 }
          , RGB { r: 255.0, g: 0.0, b: 255.0 }
          , RGB { r: 224.0, g: 172.0, b: 140.0 }
          , RGB { r: 120.0, g: 170.0, b: 230.0 }
          ]
      map (round <<< toGray gammaOff) colors `shouldEqual` [ 76.0, 150.0, 29.0, 105.0, 184.0, 162.0 ]
      map (round <<< toGray gammaSrgb) colors `shouldEqual` [ 127.0, 220.0, 76.0, 145.0, 183.0, 167.0 ]
