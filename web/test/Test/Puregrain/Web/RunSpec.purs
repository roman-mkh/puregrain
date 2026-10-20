module Test.Puregrain.Web.RunSpec (spec) where

import Prelude

import Data.Array ((..))
import Data.Array as Array
import Data.ArrayBuffer.Types (Uint8ClampedArray)
import Data.Either (Either(..), isLeft)
import Data.Foldable (all, for_)
import Data.Int (toNumber)
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Traversable (traverse)
import Effect (Effect)
import Effect.Class (liftEffect)
import Effect.Ref as Ref
import Puregrain (RGB(..), ditherImage)
import Puregrain.Web.Dither (Pipeline(..), isNeutral, kernelOf, luma, pipelineFor, toNeutral)
import Puregrain.Web.Pixels (newPixels, readRow, writeRgbRow)
import Puregrain.Web.Run (ditherPicture)
import Puregrain.Web.Settings (Colors(..), KernelName(..), PaletteName(..), Settings, chooseBayer, chooseColors, chooseGray, chooseKernel, initial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

type Picture = { width :: Int, height :: Int, pixels :: Uint8ClampedArray }

-- | A picture from a function of the position.
pictureOf :: Int -> Int -> (Int -> Int -> RGB) -> Effect Picture
pictureOf width height f = do
  pixels <- newPixels (width * height * 4)
  for_ (0 .. (height - 1)) \y -> writeRgbRow pixels width y (map (\x -> f x y) (0 .. (width - 1)))
  pure { width, height, pixels }

rowsOf :: Picture -> Effect (Array (Array RGB))
rowsOf p = traverse (readRow p.pixels p.width) (0 .. (p.height - 1))

-- | What the CLI makes of the picture, written independently of `Run`:
-- | the library's `ditherImage` on all the rows at once, gray or RGB as
-- | the CLI chooses, each channel rounded and clamped as the CLI writes
-- | PNGs (`Math.round`, which `Data.Int.round` uses).
cliResult :: Settings -> Picture -> Effect (Array (Array RGB))
cliResult settings p = do
  stored <- rowsOf p
  let
    rows = if settings.gray then map (map toNeutral) stored else stored
    grayPicture = settings.gray || all (all isNeutral) rows
    kernel = kernelOf settings.kernel
    byte v = toNumber (clamp 0 255 (Int.round v))
  pure case pipelineFor settings grayPicture of
    Just (Gray q) -> map (map (\v -> let b = byte v in RGB { r: b, g: b, b: b })) (ditherImage kernel q (map (map luma) rows))
    Just (Color q) -> map (map (\(RGB c) -> RGB { r: byte c.r, g: byte c.g, b: byte c.b })) (ditherImage kernel q rows)
    Nothing -> []

colorful :: Effect Picture
colorful = pictureOf 23 17 \x y -> RGB { r: toNumber (x * 11), g: toNumber (y * 15), b: toNumber ((x * y) `mod` 256) }

grayish :: Effect Picture
grayish = pictureOf 19 13 \x y -> let v = toNumber ((x * 13 + y * 7) `mod` 256) in RGB { r: v, g: v, b: v }

settingsToCompare :: Array Settings
settingsToCompare =
  [ chooseKernel FloydSteinberg initial
  , chooseKernel Atkinson (chooseColors (Levels 4) initial)
  -- 3 levels: 127.5 tests the rounding.
  , chooseKernel FloydSteinberg (chooseColors (Levels 3) initial)
  , chooseKernel JarvisJudiceNinke (chooseColors (Palette Websafe216) initial)
  , chooseBayer (Just 4) (chooseColors (Levels 2) initial)
  , chooseKernel FloydSteinberg (chooseBayer (Just 8) (chooseColors (Levels 4) initial))
  , chooseGray true (chooseKernel Atkinson (chooseColors (Palette C64) initial))
  , chooseGray true (chooseColors (Levels 5) initial)
  ]

spec :: Spec Unit
spec = describe "Puregrain.Web.Run" do
  it "dithers as the CLI does, row by row: the same bytes as ditherImage on the whole picture" do
    for_ [ colorful, grayish ] \makePicture -> for_ settingsToCompare \settings -> do
      p <- liftEffect makePicture
      result <- liftEffect (ditherPicture settings p (const (pure unit)))
      case result of
        Left reason -> fail reason
        Right out -> do
          got <- liftEffect (rowsOf (p { pixels = out }))
          want <- liftEffect (cliResult settings p)
          when (got /= want) (fail ("differs from the CLI's result for " <> show settings))

  it "reports progress after every hundredth of the rows, ending with all of them" do
    p <- liftEffect (pictureOf 3 250 \x y -> RGB { r: toNumber x, g: toNumber y, b: 0.0 })
    reports <- liftEffect (Ref.new [])
    _ <- liftEffect (ditherPicture (chooseColors (Levels 2) initial) p \r -> Ref.modify_ (_ <> [ r ]) reports)
    seen <- liftEffect (Ref.read reports)
    Array.last seen `shouldEqual` Just { done: 250, total: 250 }
    -- every second row of 250, as 250 / 100 rounds down to 2
    Array.length seen `shouldEqual` 125
    (Array.zipWith (\a b -> a.done < b.done) seen (Array.drop 1 seen) == map (const true) (Array.drop 1 seen)) `shouldEqual` true

  it "has nothing to dither for the original" do
    p <- liftEffect grayish
    result <- liftEffect (ditherPicture initial p (const (pure unit)))
    isLeft result `shouldEqual` true
