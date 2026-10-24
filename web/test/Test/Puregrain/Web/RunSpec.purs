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
import Puregrain.Cells (ditherCells)
import Puregrain.Machine.C64 as C64
import Puregrain.Machine.ZxSpectrum as Zx
import Puregrain.Web.Dither (Pipeline(..), isNeutral, kernelOf, luma, pipelineFor, toNeutral, zxModeOf)
import Puregrain.Web.Pixels (byteArray, newPixels, readRow, writeRgbRow)
import Puregrain.Web.Run (ditherPicture)
import Puregrain.Web.Settings (Colors(..), KernelName(..), MachineName(..), MachinePaletteName(..), PaletteName(..), Settings, Target(..), chooseBayer, chooseColors, chooseGray, chooseKernel, chooseTarget, initial)
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

jobOf :: Settings -> Picture -> { settings :: Settings, width :: Int, height :: Int, pixels :: Uint8ClampedArray, tapeName :: String }
jobOf settings p = { settings, width: p.width, height: p.height, pixels: p.pixels, tapeName: "test" }

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
    _ -> []

-- | What the CLI makes of the picture for a machine: `ditherCells` on all
-- | the rows at once, as its `ditherScreen`, and the machine's files from
-- | that, as its writers make them (the tape named as the job names it).
-- | The machine's colors are whole numbers, so no rounding.
cliScreen :: Settings -> Picture -> Effect { image :: Array (Array RGB), files :: Array { format :: String, bytes :: Either String (Array Int) } }
cliScreen settings p = do
  stored <- rowsOf p
  let
    rows = if settings.gray then map (map toNeutral) stored else stored
    kernel = kernelOf settings.kernel
  pure case pipelineFor settings false of
    Just (Screen s) -> case s.machine of
      ZxSpectrumScreen ->
        let
          d = ditherCells kernel s.rule (zxModeOf s.palette) rows
        in
          { image: d.image, files: [ { format: "scr", bytes: Zx.toScr d }, { format: "tap", bytes: Zx.toTap "test" d } ] }
      C64HiresScreen ->
        let
          d = ditherCells kernel s.rule C64.hiresScreen rows
        in
          { image: d.image, files: [ { format: "prg", bytes: C64.toHiresPrg d }, { format: "art", bytes: C64.toArtStudio d } ] }
    _ -> { image: [], files: [] }

colorful :: Effect Picture
colorful = pictureOf 23 17 \x y -> RGB { r: toNumber (x * 11), g: toNumber (y * 15), b: toNumber ((x * y) `mod` 256) }

grayish :: Effect Picture
grayish = pictureOf 19 13 \x y -> let v = toNumber ((x * 13 + y * 7) `mod` 256) in RGB { r: v, g: v, b: v }

-- | Gradients with some texture, at a machine's screen size.
screenPicture :: Int -> Int -> Effect Picture
screenPicture width height = pictureOf width height \x y ->
  RGB { r: toNumber (x * 255 / (width - 1)), g: toNumber (y * 255 / (height - 1)), b: toNumber ((x * 7 + y * y) `mod` 256) }

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

zx :: Settings
zx = chooseTarget (Machine ZxSpectrumScreen) initial

c64 :: Settings
c64 = chooseTarget (Machine C64HiresScreen) initial

machineSettingsToCompare :: Array Settings
machineSettingsToCompare =
  [ chooseBayer (Just 8) zx
  , chooseGray true (chooseKernel FloydSteinberg (chooseColors (MachineColors NormalPalette) zx))
  , chooseKernel Atkinson (chooseColors (MachineColors BrightPalette) zx)
  , zx
  , chooseBayer (Just 8) c64
  , chooseKernel Atkinson (chooseBayer (Just 4) c64)
  ]

-- | The result's pixels, or the reason there are none.
resultOf :: Settings -> Picture -> Effect (Either String { rows :: Array (Array RGB), files :: Array { format :: String, bytes :: Array Int } })
resultOf settings p = do
  result <- ditherPicture (jobOf settings p) (const (pure unit))
  case result of
    Left reason -> pure (Left reason)
    Right out -> do
      rows <- rowsOf (p { pixels = out.pixels })
      files <- traverse (\f -> { format: f.format, bytes: _ } <$> byteArray f.bytes) out.files
      pure (Right { rows, files })

spec :: Spec Unit
spec = describe "Puregrain.Web.Run" do
  it "dithers as the CLI does, row by row: the same bytes as ditherImage on the whole picture" do
    for_ [ colorful, grayish ] \makePicture -> for_ settingsToCompare \settings -> do
      p <- liftEffect makePicture
      result <- liftEffect (resultOf settings p)
      want <- liftEffect (cliResult settings p)
      case result of
        Left reason -> fail reason
        Right got -> do
          when (got.rows /= want) (fail ("differs from the CLI's result for " <> show settings))
          got.files `shouldEqual` []

  it "dithers a machine's screen as the CLI does, band by band: the same pixels and files" do
    for_ machineSettingsToCompare \settings -> do
      p <- liftEffect case settings.target of
        Machine C64HiresScreen -> screenPicture 320 200
        _ -> screenPicture 256 192
      result <- liftEffect (resultOf settings p)
      want <- liftEffect (cliScreen settings p)
      case result of
        Left reason -> fail reason
        Right got -> do
          when (got.rows /= want.image) (fail ("the picture differs from the CLI's for " <> show settings))
          map (\f -> { format: f.format, bytes: Right f.bytes }) got.files `shouldEqual` want.files

  it "dithers a machine's colors at any size, without the machine's files then" do
    p <- liftEffect (screenPicture 37 21)
    let settings = chooseKernel FloydSteinberg (chooseBayer (Just 4) zx)
    result <- liftEffect (resultOf settings p)
    want <- liftEffect (cliScreen settings p)
    case result of
      Left reason -> fail reason
      Right got -> do
        when (got.rows /= want.image) (fail "the picture differs from the CLI's")
        got.files `shouldEqual` []

  it "reports progress after every hundredth of the rows, ending with all of them" do
    p <- liftEffect (pictureOf 3 250 \x y -> RGB { r: toNumber x, g: toNumber y, b: 0.0 })
    reports <- liftEffect (Ref.new [])
    _ <- liftEffect (ditherPicture (jobOf (chooseColors (Levels 2) initial) p) \r -> Ref.modify_ (_ <> [ r ]) reports)
    seen <- liftEffect (Ref.read reports)
    Array.last seen `shouldEqual` Just { done: 250, total: 250 }
    -- every second row of 250, as 250 / 100 rounds down to 2
    Array.length seen `shouldEqual` 125
    (Array.zipWith (\a b -> a.done < b.done) seen (Array.drop 1 seen) == map (const true) (Array.drop 1 seen)) `shouldEqual` true

  it "reports progress after each band of a machine's cells, counting the rows the band brings" do
    p <- liftEffect (screenPicture 37 21)
    reports <- liftEffect (Ref.new [])
    _ <- liftEffect (ditherPicture (jobOf (chooseBayer (Just 8) zx) p) \r -> Ref.modify_ (_ <> [ r ]) reports)
    seen <- liftEffect (Ref.read reports)
    -- bands of 8, 8 and the last 5 rows
    seen `shouldEqual` [ { done: 8, total: 21 }, { done: 16, total: 21 }, { done: 21, total: 21 } ]

  it "has nothing to dither for the original" do
    p <- liftEffect grayish
    result <- liftEffect (ditherPicture (jobOf initial p) (const (pure unit)))
    isLeft result `shouldEqual` true
