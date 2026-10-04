module Test.Puregrain.PresetsSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Foldable (for_)
import Data.Int (toNumber)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import Test.QuickCheck (arbitrary, (===))
import Test.QuickCheck.Gen (chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Test.Spec.QuickCheck (quickCheck)

import Puregrain.Palette (compilePalette, distance2, nearestColor, nearestColorFast)
import Puregrain.Palette.Presets (ansi16, ansi256, blackWhite, c64, cga16, websafe216, zxSpectrum)
import Puregrain.Pixel (RGB(..))
import Puregrain.Quantize (nearestLevel, perChannel)
import Test.Puregrain.Arbitrary (TestKernel(..), TestRGB(..), TestSample(..))
import Test.Puregrain.Util (dither, runAtOrigin, websafeSteps)

rgb :: Int -> Int -> Int -> RGB
rgb r g b = RGB { r: toNumber r, g: toNumber g, b: toNumber b }

black :: RGB
black = rgb 0 0 0

white :: RGB
white = rgb 255 255 255

distinctCount :: NonEmptyArray RGB -> Int
distinctCount = Array.length <<< Array.nubEq <<< NEA.toArray

-- | Bit `n` (1, 2, 4, 8) of a color index, as 0 or 1.
bit :: Int -> Int -> Int
bit n i = (i / n) `mod` 2

presets :: Array (Tuple String (NonEmptyArray RGB))
presets =
  [ Tuple "blackWhite" blackWhite, Tuple "websafe216" websafe216, Tuple "cga16" cga16
  , Tuple "ansi16" ansi16, Tuple "ansi256" ansi256, Tuple "c64" c64, Tuple "zxSpectrum" zxSpectrum
  ]

spec :: Spec Unit
spec = describe "Puregrain.Palette.Presets" do

  describe "blackWhite" do
    it "is exactly black, then white" do
      NEA.toArray blackWhite `shouldEqual` [ black, white ]

    -- For a neutral pixel (v, v, v) the squared distances are 3v² to
    -- black and 3(255 - v)² to white, so black wins iff v <= 127.5 —
    -- including the exact tie at 127.5, which goes to the earlier entry.
    it "on neutral pixels, acts as a threshold at 127.5 (ties go to black)" do
      quickCheck \(TestSample v) ->
        runAtOrigin (nearestColor blackWhite) (RGB { r: v, g: v, b: v })
          === if v <= 127.5 then black else white

    -- RGB distance is not perceptual: pure green's luma (~150) is well
    -- above mid-gray, yet it's nearer to black (255²) than to white
    -- (2·255²). Pinned down here because it's a real, visible difference
    -- from converting to gray and thresholding — and the reason a
    -- perceptual metric (distance2Lab, see TODO.md) is on the list.
    it "on saturated colors, follows RGB distance, not brightness (pure green -> black)" do
      let q = runAtOrigin (nearestColor blackWhite)
      q (RGB { r: 0.0, g: 255.0, b: 0.0 }) `shouldEqual` black
      q (RGB { r: 255.0, g: 0.0, b: 0.0 }) `shouldEqual` black
      q (RGB { r: 255.0, g: 255.0, b: 0.0 }) `shouldEqual` white

  describe "websafe216" do
    let
      steps = NEA.toArray websafeSteps
      colors = NEA.toArray websafe216

    it "has exactly 216 colors" do
      NEA.length websafe216 `shouldEqual` 216

    it "has no duplicates" do
      Array.length (Array.nubEq colors) `shouldEqual` 216

    it "uses only the six web-safe channel values, in every channel" do
      let onStep x = Array.elem x steps
      Array.all (\(RGB c) -> onStep c.r && onStep c.g && onStep c.b) colors `shouldEqual` true

    it "starts at black and ends at white (r slowest, b fastest)" do
      NEA.head websafe216 `shouldEqual` black
      NEA.last websafe216 `shouldEqual` white
      NEA.index websafe216 1 `shouldEqual` Just (RGB { r: 0.0, g: 0.0, b: 51.0 })
      NEA.index websafe216 6 `shouldEqual` Just (RGB { r: 0.0, g: 51.0, b: 0.0 })
      NEA.index websafe216 36 `shouldEqual` Just (RGB { r: 51.0, g: 0.0, b: 0.0 })

    -- vectorED and scalarED agree here, and not by accident: web-safe
    -- is a full Cartesian product of per-channel steps, and squared
    -- Euclidean distance is a sum of independent per-channel terms, so
    -- the nearest cube color is exactly the nearest step in each
    -- channel separately. Exact ties agree too: the cube's r-g-b order
    -- makes "earliest tied entry" mean "lower step in every tied
    -- channel", which is also `nearestLevel`'s earlier-wins pick on
    -- ascending steps. (Float addition is monotonic, so rounding can
    -- only turn a strict difference into a tie, never reverse it — the
    -- only possible disagreement needs a random channel value within
    -- ~1e-13 of a midpoint between steps; not a practical concern.)
    it "nearest color (vectorED) == perChannel nearest step (scalarED), for any pixel" do
      let
        vectorED = nearestColorFast (compilePalette distance2 websafe216)
        scalarED = runAtOrigin (perChannel (nearestLevel websafeSteps))
      quickCheck \(TestRGB pixel) ->
        vectorED pixel === scalarED pixel

  describe "cga16 (IBM PC: CGA RGBI, EGA/VGA default, DOS/Linux console)" do
    it "has 16 distinct colors" do
      NEA.length cga16 `shouldEqual` 16
      distinctCount cga16 `shouldEqual` 16

    -- Independent of the table in the code: CGA index bits are 1 blue,
    -- 2 green, 4 red, 8 intensity; each set color bit gives 0xAA, the
    -- intensity bit adds 0x55 to every channel. The monitor's one
    -- exception: color 6 is brown (0xAA, 0x55, 0x00), not dark yellow.
    it "follows the RGBI rule, with brown at index 6" do
      let
        expected i
          | i == 6 = rgb 0xAA 0x55 0x00
          | otherwise =
              let intensity = 0x55 * bit 8 i
              in rgb (0xAA * bit 4 i + intensity) (0xAA * bit 2 i + intensity) (0xAA * bit 1 i + intensity)
      NEA.toArray cga16 `shouldEqual` map expected (0 .. 15)

  describe "ansi16 (xterm's defaults)" do
    it "has 16 distinct colors" do
      NEA.length ansi16 `shouldEqual` 16
      distinctCount ansi16 `shouldEqual` 16

    it "matches xterm's X11 colors (red3, blue2, gray90, gray50, rgb:5c/5c/ff)" do
      NEA.index ansi16 0 `shouldEqual` Just black
      NEA.index ansi16 1 `shouldEqual` Just (rgb 205 0 0)
      NEA.index ansi16 4 `shouldEqual` Just (rgb 0 0 238)
      NEA.index ansi16 7 `shouldEqual` Just (rgb 229 229 229)
      NEA.index ansi16 8 `shouldEqual` Just (rgb 127 127 127)
      NEA.index ansi16 12 `shouldEqual` Just (rgb 92 92 255)
      NEA.index ansi16 15 `shouldEqual` Just white

  describe "ansi256 (xterm's 256 colors)" do
    let colors = NEA.toArray ansi256

    it "has 256 entries, starting with ansi16" do
      NEA.length ansi256 `shouldEqual` 256
      Array.take 16 colors `shouldEqual` NEA.toArray ansi16

    it "has 249 distinct colors: the cube repeats 7 of ansi16's" do
      distinctCount ansi256 `shouldEqual` 249

    it "has the 6×6×6 cube at 16–231, levels 0, 95, 135, 175, 215, 255 (index 16 + 36r + 6g + b)" do
      let
        levels = [ 0, 95, 135, 175, 215, 255 ]
        cube = do
          r <- levels
          g <- levels
          b <- levels
          pure (rgb r g b)
      Array.slice 16 232 colors `shouldEqual` cube

    it "has 24 grays at 232–255, from 8 to 238 in steps of 10" do
      let grays = Array.slice 232 256 colors
      Array.length grays `shouldEqual` 24
      Array.head grays `shouldEqual` Just (rgb 8 8 8)
      Array.last grays `shouldEqual` Just (rgb 238 238 238)
      Array.zipWith (\(RGB a) (RGB b) -> [ b.r - a.r, b.g - a.g, b.b - a.b ]) grays (Array.drop 1 grays)
        `shouldEqual` Array.replicate 23 [ 10.0, 10.0, 10.0 ]

  describe "c64 (Pepto's PAL palette)" do
    it "has 16 distinct colors" do
      NEA.length c64 `shouldEqual` 16
      distinctCount c64 `shouldEqual` 16

    it "matches Pepto's published values, in VIC-II index order" do
      NEA.index c64 0 `shouldEqual` Just black
      NEA.index c64 1 `shouldEqual` Just white
      NEA.index c64 2 `shouldEqual` Just (rgb 0x68 0x37 0x2B)
      NEA.index c64 9 `shouldEqual` Just (rgb 0x43 0x39 0x00)
      NEA.index c64 11 `shouldEqual` Just (rgb 0x44 0x44 0x44)
      NEA.index c64 14 `shouldEqual` Just (rgb 0x6C 0x5E 0xB5)
      NEA.index c64 15 `shouldEqual` Just (rgb 0x95 0x95 0x95)

  describe "zxSpectrum" do
    it "has 15 distinct colors (bright black is just black)" do
      NEA.length zxSpectrum `shouldEqual` 15
      distinctCount zxSpectrum `shouldEqual` 15

    -- Independent of the code's list: ZX color codes are bit 1 blue,
    -- bit 2 red, bit 4 green; normal brightness 0xD8, BRIGHT 0xFF.
    it "follows the ZX color codes: normal 0–7 at 0xD8, then bright 1–7 at 0xFF" do
      let color v c = rgb (v * bit 2 c) (v * bit 4 c) (v * bit 1 c)
      NEA.toArray zxSpectrum `shouldEqual` (map (color 0xD8) (0 .. 7) <> map (color 0xFF) (1 .. 7))

  describe "every preset" do
    for_ presets \(Tuple name palette) ->
      it (name <> ": an image made only of its colors dithers to itself (zero error), for any kernel") do
        quickCheck do
          TestKernel kernel <- arbitrary
          width <- chooseInt 1 6
          height <- chooseInt 1 6
          image <- vectorOf height (vectorOf width (elements palette))
          pure (dither kernel (nearestColor palette) image === image)
