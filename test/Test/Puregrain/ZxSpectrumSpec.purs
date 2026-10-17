module Test.Puregrain.ZxSpectrumSpec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Char (toCharCode)
import Data.Either (Either(..), either, hush)
import Data.Foldable (all, and, foldl)
import Data.Int (pow)
import Data.Int.Bits (xor)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String.CodeUnits (toCharArray)
import Data.Traversable (traverse)
import Partial.Unsafe (unsafeCrashWith)
import Test.QuickCheck (class Arbitrary, Result(..), (===))
import Test.QuickCheck.Gen (Gen, chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck, quickCheck')

import Puregrain.Cells (cellColors, ditherCells)
import Puregrain.Machine.ZxSpectrum (Attribute, attributePalette, attributes, bright, brightScreen, ink, normalScreen, paper, screen, toScr, toTap)
import Puregrain.Palette (distance2)
import Puregrain.Pixel (RGB(..))
import Test.Puregrain.Arbitrary (TestCellQuantizer(..), TestKernel(..))
import Test.Puregrain.Util (mentions)

-- | A color code's color, from the code's bits (1 blue, 2 red, 4 green),
-- | written independently of the preset: 0xD8 normal, 0xFF bright.
expectedColor :: Boolean -> Int -> RGB
expectedColor isBright code = RGB { r: on 2, g: on 4, b: on 1 }
  where
  level = if isBright then 255.0 else 216.0
  on bit = if (code / bit) `mod` 2 == 1 then level else 0.0

colorsOf :: Attribute -> NonEmptyArray RGB
colorsOf = cellColors <<< attributePalette

-- | Two attributes look the same if their colors are the same set.
sameColors :: Attribute -> Attribute -> Boolean
sameColors a b = all (\c -> NEA.elem c (colorsOf b)) (colorsOf a) && all (\c -> NEA.elem c (colorsOf a)) (colorsOf b)

all71 :: Array Attribute
all71 = NEA.toArray attributes

-- | The attribute with these codes. Crashes for one that `attributes`
-- | doesn't have; the tests ask only for ones it has.
attribute :: Int -> Int -> Boolean -> Attribute
attribute i p b = case Array.find (\a -> ink a == i && paper a == p && bright a == b) all71 of
  Just a -> a
  Nothing -> unsafeCrashWith "no such attribute"

-- | Black ink on white paper, the Spectrum's default attribute (56).
blackOnWhite :: Attribute
blackOnWhite = attribute 0 7 false

-- | Cells and pixels, as `ditherCells` returns them and `toScr` takes them.
type Screen = { cells :: Array (Array Attribute), image :: Array (Array RGB) }

-- | A width × height grid from a function of the position (x, y).
grid :: forall a. Int -> Int -> (Int -> Int -> a) -> Array (Array a)
grid width height f = map (\y -> map (\x -> f x y) (Array.range 0 (width - 1))) (Array.range 0 (height - 1))

-- | A whole screen, 32 × 24 cells of 8 × 8 pixels, from each cell's
-- | attribute and each pixel's color by position.
screenOf :: (Int -> Int -> Attribute) -> (Int -> Int -> RGB) -> Screen
screenOf cellAt pixelAt = { cells: grid 32 24 cellAt, image: grid 256 192 pixelAt }

-- | Black ink on white paper everywhere; white pixels, except black ones
-- | at the given points.
inkAt :: Array { x :: Int, y :: Int } -> Screen
inkAt points = screenOf (\_ _ -> blackOnWhite) \x y ->
  if Array.elem { x, y } points then expectedColor false 0 else expectedColor false 7

-- | The bytes other than `usual`, with their offsets: a short answer to
-- | compare, and a readable failure.
unusual :: Int -> Array Int -> Array { offset :: Int, value :: Int }
unusual usual bytes = Array.filter (\b -> b.value /= usual) (Array.mapWithIndex (\offset value -> { offset, value }) bytes)

-- | What an attribute byte holds.
type Codes = { ink :: Int, paper :: Int, bright :: Boolean, flash :: Boolean }

codesOf :: Attribute -> Codes
codesOf a = { ink: ink a, paper: paper a, bright: bright a, flash: false }

-- | Reads a .scr file back, written independently of `toScr`: it finds
-- | each pixel's byte by the forward address formula (`toScr` goes from
-- | the byte to the row), with arithmetic instead of bit operations, and
-- | the colors from the code bits.
readScr :: Array Int -> { cells :: Array (Array Codes), image :: Array (Array RGB) }
readScr bytes = { cells: grid 32 24 codesAt, image: grid 256 192 pixelAt }
  where
  byteAt i = fromMaybe 0 (Array.index bytes i)
  codesAt column row =
    let
      a = byteAt (6144 + row * 32 + column)
    in
      { ink: a `mod` 8, paper: (a / 8) `mod` 8, bright: (a / 64) `mod` 2 == 1, flash: a >= 128 }
  pixelAt x y =
    let
      address = (y / 64) * 2048 + (y `mod` 8) * 256 + ((y / 8) `mod` 8) * 32 + x / 8
      isInk = (byteAt address / pow 2 (7 - x `mod` 8)) `mod` 2 == 1
      codes = codesAt (x / 8) (y / 8)
    in
      expectedColor codes.bright (if isInk then codes.ink else codes.paper)

-- | One block of a tape: its flag and its bytes, without the length and
-- | the checksum.
type TapeBlock = { flag :: Int, bytes :: Array Int }

-- | Reads a .tap file's blocks, written independently of `toTap`: each
-- | block's two-byte length, low byte first, and its checksum, which makes
-- | the XOR of all its bytes, flag and checksum included, zero.
readTape :: Array Int -> Either String (Array TapeBlock)
readTape tape = go 0 []
  where
  go at blocks =
    if at == Array.length tape then Right blocks
    else case Array.index tape at, Array.index tape (at + 1) of
      Just low, Just high ->
        let
          n = low + 256 * high
          body = Array.slice (at + 2) (at + 2 + n) tape
        in
          if n < 2 || Array.length body /= n then Left ("the block at " <> show at <> " is cut short")
          else if foldl xor 0 body /= 0 then Left ("the block at " <> show at <> " has a wrong checksum")
          else go (at + 2 + n) (Array.snoc blocks { flag: fromMaybe (-1) (Array.head body), bytes: Array.slice 1 (n - 1) body })
      _, _ -> Left ("the length at " <> show at <> " is cut short")

-- | A tape name's codes, padded with spaces to 10.
nameCodes :: String -> Array Int
nameCodes name = codes <> Array.replicate (10 - Array.length codes) 32
  where
  codes = map toCharCode (toCharArray name)

-- | Valid cells, `columns` × `rows` of them: each cell a random
-- | attribute, each pixel one of that attribute's colors.
genScreen :: Int -> Int -> Gen Screen
genScreen = genScreenFrom attributes

-- | As `genScreen`, with the cells' attributes drawn from the given ones.
genScreenFrom :: NonEmptyArray Attribute -> Int -> Int -> Gen Screen
genScreenFrom candidates columns rows = do
  cells <- vectorOf rows (vectorOf columns (elements candidates))
  image <- Array.concat <$> traverse pixelRows cells
  pure { cells, image }
  where
  -- The 8 pixel rows of one row of cells.
  pixelRows row = vectorOf 8 (Array.concat <$> traverse (\a -> vectorOf 8 (elements (colorsOf a))) row)

-- | A picture made only of valid cells, 1 to 3 cells each way.
newtype TestScreen = TestScreen (Array (Array RGB))

instance Arbitrary TestScreen where
  arbitrary = do
    columns <- chooseInt 1 3
    rows <- chooseInt 1 3
    TestScreen <<< _.image <$> genScreen columns rows

-- | A picture made only of valid cells of normal brightness, or only of
-- | bright ones (black included), 1 to 3 cells each way.
newtype NormalPicture = NormalPicture (Array (Array RGB))
newtype BrightPicture = BrightPicture (Array (Array RGB))

instance Arbitrary NormalPicture where
  arbitrary = do
    columns <- chooseInt 1 3
    rows <- chooseInt 1 3
    NormalPicture <<< _.image <$> genScreenFrom normalScreen.candidates columns rows

instance Arbitrary BrightPicture where
  arbitrary = do
    columns <- chooseInt 1 3
    rows <- chooseInt 1 3
    BrightPicture <<< _.image <$> genScreenFrom brightScreen.candidates columns rows

-- | A whole screen of valid cells, 256 × 192 pixels.
newtype FullScreen = FullScreen Screen

instance Arbitrary FullScreen where
  arbitrary = FullScreen <$> genScreen 32 24

spec :: Spec Unit
spec = describe "Puregrain.Machine.ZxSpectrum" do

  describe "attributes" do
    it "has the 71 cell palettes the Spectrum can show, all looking different" do
      Array.length all71 `shouldEqual` 71
      Array.length (Array.nubByEq sameColors all71) `shouldEqual` 71

    it "follows the Spectrum's convention: ink the darker color, and all black without BRIGHT" do
      Array.filter (\a -> ink a > paper a) all71 `shouldEqual` []
      Array.filter (\a -> bright a && ink a == 0 && paper a == 0) all71 `shouldEqual` []

    it "lists the 15 single colors first, then the pairs, nearest first" do
      let
        singles = Array.takeWhile (\a -> ink a == paper a) all71
        pairs = Array.drop (Array.length singles) all71
        spread a = distance2 (expectedColor (bright a) (ink a)) (expectedColor (bright a) (paper a))
        spreads = map spread pairs
      Array.length singles `shouldEqual` 15
      Array.filter (\a -> ink a == paper a) pairs `shouldEqual` []
      and (Array.zipWith (<=) spreads (Array.drop 1 spreads)) `shouldEqual` true

    it "uses the Spectrum's colors, 0xD8 at normal brightness and 0xFF with BRIGHT" do
      let
        expected a =
          if ink a == paper a then NEA.singleton (expectedColor (bright a) (ink a))
          else NEA.cons' (expectedColor (bright a) (ink a)) [ expectedColor (bright a) (paper a) ]
      Array.filter (\a -> colorsOf a /= expected a) all71 `shouldEqual` []

  describe "screen" do
    -- The size needs its own check: a valid picture stays unchanged with
    -- smaller cells too, since a piece of a valid cell is valid.
    it "is 8x8 cells, with the attributes in their order and their colors" do
      screen.size `shouldEqual` { width: 8, height: 8 }
      NEA.toArray screen.candidates `shouldEqual` all71
      map (cellColors <<< screen.palette) all71 `shouldEqual` map colorsOf all71

  describe "normalScreen and brightScreen" do
    it "normalScreen has the 36 attributes without BRIGHT, in their usual order, and the same cells and colors" do
      Array.length (NEA.toArray normalScreen.candidates) `shouldEqual` 36
      NEA.toArray normalScreen.candidates `shouldEqual` Array.filter (not <<< bright) all71
      normalScreen.size `shouldEqual` { width: 8, height: 8 }
      map (cellColors <<< normalScreen.palette) all71 `shouldEqual` map colorsOf all71

    it "brightScreen has black and the 35 attributes with BRIGHT, in their usual order, and the same cells and colors" do
      let black a = ink a == 0 && paper a == 0
      Array.length (NEA.toArray brightScreen.candidates) `shouldEqual` 36
      NEA.toArray brightScreen.candidates `shouldEqual` Array.filter (\a -> bright a || black a) all71
      Array.filter (\a -> not (bright a) && not (black a)) (NEA.toArray brightScreen.candidates) `shouldEqual` []
      brightScreen.size `shouldEqual` { width: 8, height: 8 }
      map (cellColors <<< brightScreen.palette) all71 `shouldEqual` map colorsOf all71

    it "each leaves a picture made only of its own valid cells unchanged, with any kernel and rule" do
      quickCheck \(TestKernel kernel) (TestCellQuantizer rule) (NormalPicture picture) ->
        (ditherCells kernel rule normalScreen picture).image === picture
      quickCheck \(TestKernel kernel) (TestCellQuantizer rule) (BrightPicture picture) ->
        (ditherCells kernel rule brightScreen picture).image === picture

  describe "dithering with the attributes" do
    -- Holds only because of the order: normal white, for example, lies on
    -- the segment from black to bright white, so a cell of black and
    -- normal white scores 0 with both pairs; the nearer pair must come
    -- first, or the white pixels would turn bright.
    -- With `orderedInCell` it holds because every threshold lies strictly
    -- between 0 and 1: ink is at 0, paper at 1.
    it "leaves a picture made only of valid cells unchanged, with any kernel and rule" do
      quickCheck \(TestKernel kernel) (TestCellQuantizer rule) (TestScreen picture) ->
        (ditherCells kernel rule screen picture).image === picture

  describe "toScr" do
    it "puts each pixel at the Spectrum's address: the leftmost pixel in the highest bit, the rows interleaved" do
      let bitmapOf points = map (unusual 0 <<< Array.take 6144) (toScr (inkAt points))
      bitmapOf [ { x: 0, y: 0 } ] `shouldEqual` Right [ { offset: 0, value: 128 } ]
      bitmapOf [ { x: 7, y: 0 } ] `shouldEqual` Right [ { offset: 0, value: 1 } ]
      bitmapOf [ { x: 8, y: 0 } ] `shouldEqual` Right [ { offset: 1, value: 128 } ]
      -- One pixel row down is 256 bytes on, one cell row down 32, and one
      -- third of the screen (64 rows) down 2048.
      bitmapOf [ { x: 0, y: 1 } ] `shouldEqual` Right [ { offset: 256, value: 128 } ]
      bitmapOf [ { x: 0, y: 8 } ] `shouldEqual` Right [ { offset: 32, value: 128 } ]
      bitmapOf [ { x: 0, y: 64 } ] `shouldEqual` Right [ { offset: 2048, value: 128 } ]
      bitmapOf [ { x: 255, y: 191 } ] `shouldEqual` Right [ { offset: 6143, value: 1 } ]

    it "writes 6912 bytes, the attributes after the bitmap, row by row: BRIGHT x 64 + paper x 8 + ink" do
      let
        -- Cell column 2 of cell row 1: bright blue ink on bright yellow
        -- paper, all paper.
        special x y = x == 2 && y == 1
        bytes = toScr $ screenOf (\x y -> if special x y then attribute 1 6 true else blackOnWhite) \x y ->
          if special (x / 8) (y / 8) then expectedColor true 6 else expectedColor false 7
      map Array.length bytes `shouldEqual` Right 6912
      map (unusual 0 <<< Array.take 6144) bytes `shouldEqual` Right []
      map (unusual 56 <<< Array.drop 6144) bytes `shouldEqual` Right [ { offset: 32 + 2, value: 64 + 6 * 8 + 1 } ]

    it "gives a single-color cell the bit 0 everywhere, like a pair's paper" do
      let
        -- The first cell is white alone, with white pixels; all the
        -- others are black on white, with black (ink) pixels.
        bytes = toScr $ screenOf (\x y -> if x == 0 && y == 0 then attribute 7 7 false else blackOnWhite) \x y ->
          if x < 8 && y < 8 then expectedColor false 7 else expectedColor false 0
      map (unusual 255 <<< Array.take 6144) bytes `shouldEqual` Right (map (\row -> { offset: row * 256, value: 0 }) (Array.range 0 7))

    it "can be read back: an independent reader gives the same cells and pixels, for any valid screen" do
      -- 10 screens instead of 100: each has 49,152 pixels.
      quickCheck' 10 \(FullScreen s) -> case toScr s of
        Left message -> Failed message
        Right bytes ->
          let
            decoded = readScr bytes
          in
            if Array.length bytes /= 6912 then Failed ("got " <> show (Array.length bytes) <> " bytes, not 6912")
            else if decoded.cells /= map (map codesOf) s.cells then Failed "the attributes read back differ"
            else if decoded.image /= s.image then Failed "the pixels read back differ"
            else Success

    it "rejects an image that isn't 256x192, cells that don't match it, and a pixel that isn't one of its cell's colors" do
      let
        valid = inkAt []
        failure = either Just (const Nothing) <<< toScr
      failure (valid { image = map (Array.drop 1) valid.image }) `shouldSatisfy` mentions "the image must be 256x192, a ZX Spectrum screen; it's 255x192"
      failure (valid { image = Array.drop 1 valid.image }) `shouldSatisfy` mentions "it's 256x191"
      failure (valid { image = [] }) `shouldSatisfy` mentions "it's 0x0"
      failure (valid { image = Array.mapWithIndex (\y row -> if y == 5 then Array.drop 1 row else row) valid.image })
        `shouldSatisfy` mentions "it's 192 rows of different lengths"
      failure (valid { cells = map (Array.drop 1) valid.cells }) `shouldSatisfy` mentions "the cells must form a 32x24 grid, one per 8x8 cell of the image; they're 31x24"
      -- Bright white in a cell of normal black and white.
      failure (screenOf (\_ _ -> blackOnWhite) \x y -> if x == 3 && y == 5 then expectedColor true 7 else expectedColor false 7)
        `shouldSatisfy` mentions "pixel (3, 5) isn't one of its cell's colors"

  describe "toTap" do
    it "puts a BASIC loader that starts by itself on the tape, then the screen as a CODE file" do
      let
        white = inkAt []
        -- Two-byte numbers, low byte first.
        le n = [ n `mod` 256, n / 256 ]
        header kind length start param2 = [ kind ] <> nameCodes "sphere" <> le length <> le start <> le param2
        -- 10 LOAD "" SCREEN$: PAUSE 0: the line number, high byte first;
        -- the length of the rest; LOAD, the quotes, SCREEN$, the colon,
        -- PAUSE, the digit 0, the number marker and 0's five bytes, ENTER.
        program = [ 0, 10, 14, 0, 0xEF, 0x22, 0x22, 0xAA, 0x3A, 0xF2, 0x30, 0x0E, 0, 0, 0, 0, 0, 0x0D ]
        tape = toTap "sphere" white
      map Array.length tape `shouldEqual` Right 6980
      map (Array.take 3) (tape >>= readTape) `shouldEqual` Right
        [ { flag: 0, bytes: header 0 18 10 18 }
        , { flag: 255, bytes: program }
        , { flag: 0, bytes: header 3 6912 16384 32768 }
        ]
      -- The screen's bytes, compared as a whole: a failure would print
      -- 6912 numbers otherwise.
      map (\blocks -> map _.bytes (Array.index blocks 3) == hush (toScr white)) (tape >>= readTape) `shouldEqual` Right true

    it "can be read back: its blocks hold the loader's and the screen's, for any valid screen" do
      -- 5 screens instead of 100: each has 49,152 pixels.
      quickCheck' 5 \(FullScreen s) ->
        case toTap "zx" s >>= readTape of
          Left problem -> Failed problem
          Right blocks ->
            if map _.flag blocks /= [ 0, 255, 0, 255 ] then Failed ("flags " <> show (map _.flag blocks))
            else if map _.bytes (Array.index blocks 3) /= hush (toScr s) then Failed "the screen's bytes differ"
            else Success

    it "pads the name with spaces, and rejects a name that's too long or holds other characters" do
      let
        valid = inkAt []
        failure name = either Just (const Nothing) (toTap name valid)
      map (map (Array.slice 1 11 <<< _.bytes) <<< Array.head) (toTap "zx" valid >>= readTape) `shouldEqual` Right (Just (nameCodes "zx"))
      failure "0123456789" `shouldEqual` Nothing
      failure "0123456789A" `shouldSatisfy` mentions "a tape name has at most 10 characters; \"0123456789A\" has 11"
      failure "schön" `shouldSatisfy` mentions "only printable ASCII characters"
      failure "a\tb" `shouldSatisfy` mentions "only printable ASCII characters"
      either Just (const Nothing) (toTap "zx" (valid { image = [] })) `shouldSatisfy` mentions "the image must be 256x192"
