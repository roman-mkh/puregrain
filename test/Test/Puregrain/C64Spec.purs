module Test.Puregrain.C64Spec (spec) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Char (fromCharCode)
import Data.Either (Either(..), either)
import Data.Foldable (all, and, any, sum)
import Data.Int (pow, toNumber)
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.String (Pattern(..), contains, joinWith)
import Data.String.CodeUnits as CodeUnits
import Data.Traversable (traverse)
import Partial.Unsafe (unsafeCrashWith)
import Test.QuickCheck (class Arbitrary, Result(..), (===))
import Test.QuickCheck.Gen (Gen, chooseInt, elements, vectorOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Test.Spec.QuickCheck (quickCheck, quickCheck')

import Puregrain.Cells (cellColors, ditherCells)
import Puregrain.Machine.C64 (HiresCell, background, foreground, hiresCells, hiresPalette, hiresScreen, toArtStudio, toHiresPrg)
import Puregrain.Pixel (RGB(..))
import Test.Puregrain.Arbitrary (TestCellQuantizer(..), TestKernel(..))
import Test.Puregrain.Util (mentions)

-- | The 16 colors by code, written out independently of the preset:
-- | Colodore's values, as in VICE's data/C64/colodore.vpl.
colodore :: Array RGB
colodore = map hex
  [ 0x000000, 0xFFFFFF, 0x96282E, 0x5BD6CE, 0x9F2DAD, 0x41B936, 0x2724C4, 0xEFF347
  , 0x9F4815, 0x5E3500, 0xDA5F66, 0x474747, 0x787878, 0x91FF84, 0x6864FF, 0xAEAEAE
  ]
  where
  hex n = RGB { r: toNumber (n / 65536), g: toNumber ((n / 256) `mod` 256), b: toNumber (n `mod` 256) }

expectedColor :: Int -> RGB
expectedColor code = fromMaybe (RGB { r: -1.0, g: -1.0, b: -1.0 }) (Array.index colodore code)

luma :: RGB -> Number
luma (RGB p) = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b

-- | The squared distance between two colors, written out here.
distance :: RGB -> RGB -> Number
distance (RGB a) (RGB b) = sum (map (\d -> d * d) [ a.r - b.r, a.g - b.g, a.b - b.b ])

colorsOf :: HiresCell -> NonEmptyArray RGB
colorsOf = cellColors <<< hiresPalette

-- | Two cells look the same if their colors are the same set.
sameColors :: HiresCell -> HiresCell -> Boolean
sameColors a b = all (\c -> NEA.elem c (colorsOf b)) (colorsOf a) && all (\c -> NEA.elem c (colorsOf a)) (colorsOf b)

all136 :: Array HiresCell
all136 = NEA.toArray hiresCells

-- | The hires cell with these colors. Crashes for one that `hiresCells`
-- | doesn't have; the tests ask only for ones it has.
hiresCell :: Int -> Int -> HiresCell
hiresCell fg bg = case Array.find (\c -> foreground c == fg && background c == bg) all136 of
  Just c -> c
  Nothing -> unsafeCrashWith "no such hires cell"

-- | Black on white: black is the darker, so it's the foreground.
blackOnWhite :: HiresCell
blackOnWhite = hiresCell 0 1

-- | Cells and pixels, as `ditherCells` returns them and `toHiresPrg`
-- | takes them.
type Screen = { cells :: Array (Array HiresCell), image :: Array (Array RGB) }

-- | A width × height grid from a function of the position (x, y).
grid :: forall a. Int -> Int -> (Int -> Int -> a) -> Array (Array a)
grid width height f = map (\y -> map (\x -> f x y) (Array.range 0 (width - 1))) (Array.range 0 (height - 1))

-- | A whole screen, 40 × 25 cells of 8 × 8 pixels, from each cell's
-- | colors and each pixel's color by position.
screenOf :: (Int -> Int -> HiresCell) -> (Int -> Int -> RGB) -> Screen
screenOf cellAt pixelAt = { cells: grid 40 25 cellAt, image: grid 320 200 pixelAt }

-- | Black on white everywhere; white pixels, except black ones at the
-- | given points.
foregroundAt :: Array { x :: Int, y :: Int } -> Screen
foregroundAt points = screenOf (\_ _ -> blackOnWhite) \x y ->
  if Array.elem { x, y } points then expectedColor 0 else expectedColor 1

-- | The bytes other than `usual`, with their offsets: a short answer to
-- | compare, and a readable failure.
unusual :: Int -> Array Int -> Array { offset :: Int, value :: Int }
unusual usual bytes = Array.filter (\b -> b.value /= usual) (Array.mapWithIndex (\offset value -> { offset, value }) bytes)

-- | The bytes of a .prg that load from the address `from` up to `to`
-- | (exclusive): the file loads at 2049, after its two-byte load address.
region :: Int -> Int -> Array Int -> Array Int
region from to = Array.slice (from - 2049 + 2) (to - 2049 + 2)

-- | The byte a .prg loads at `address`, or 0 past its end.
loadedAt :: Array Int -> Int -> Int
loadedAt bytes address = fromMaybe 0 (Array.index bytes (address - 2049 + 2))

-- | What a cell's color byte holds.
type Codes = { foreground :: Int, background :: Int }

codesOf :: HiresCell -> Codes
codesOf c = { foreground: foreground c, background: background c }

-- | Reads a picture back, written independently of the library: each
-- | pixel's byte by the forward address formula (the library goes from the
-- | byte to the pixels), with arithmetic instead of bit operations, and
-- | the colors from the list above. `bitmapAt` and `colorsAt` give the
-- | bitmap's and the colors' bytes by their offset in each.
readPicture :: (Int -> Int) -> (Int -> Int) -> { cells :: Array (Array Codes), image :: Array (Array RGB) }
readPicture bitmapAt colorsAt = { cells: grid 40 25 codesAt, image: grid 320 200 pixelAt }
  where
  codesAt column row =
    let
      c = colorsAt (row * 40 + column)
    in
      { foreground: c / 16, background: c `mod` 16 }
  pixelAt x y =
    let
      byte = bitmapAt ((y / 8) * 320 + (x / 8) * 8 + y `mod` 8)
      isForeground = (byte / pow 2 (7 - x `mod` 8)) `mod` 2 == 1
      codes = codesAt (x / 8) (y / 8)
    in
      expectedColor (if isForeground then codes.foreground else codes.background)

-- | The picture in a .prg: the bitmap loads at 8192, the colors at 3072.
readPrg :: Array Int -> { cells :: Array (Array Codes), image :: Array (Array RGB) }
readPrg bytes = readPicture (\o -> loadedAt bytes (8192 + o)) (\o -> loadedAt bytes (3072 + o))

-- | The picture in an Art Studio file, as RECOIL reads one: the bitmap
-- | from offset 2, after the load address, the colors from offset 8002.
readArt :: Array Int -> { cells :: Array (Array Codes), image :: Array (Array RGB) }
readArt bytes = readPicture (\o -> byteAt (2 + o)) (\o -> byteAt (8002 + o))
  where
  byteAt i = fromMaybe 0 (Array.index bytes i)

-- | The BASIC keywords the viewer uses, with their one-byte tokens
-- | (C64-Wiki: BASIC token), written out independently of the library.
keywords :: Array { name :: String, token :: Int }
keywords =
  [ { name: "PEEK", token: 0xC2 }, { name: "POKE", token: 0x97 }, { name: "AND", token: 0xAF }
  , { name: "OR", token: 0xB0 }, { name: "GET", token: 0xA1 }, { name: "IF", token: 0x8B }
  , { name: "THEN", token: 0xA7 }, { name: "=", token: 0xB2 }
  ]

-- | Lists the BASIC program of a .prg as LIST would, read independently of
-- | `toHiresPrg`: from 2049, line by line through each line's link, which
-- | must point just past the line's 0. `Left` for a wrong link, an unknown
-- | token, or a keyword stored as plain letters, which the C64 wouldn't
-- | run (the viewer quotes nothing, so no keyword is meant as text).
listing :: Array Int -> Either String (Array String)
listing bytes = go 2049 []
  where
  go address lines =
    let
      link = loadedAt bytes address + 256 * loadedAt bytes (address + 1)
      number = loadedAt bytes (address + 2) + 256 * loadedAt bytes (address + 3)
      text = Array.takeWhile (_ /= 0) (Array.drop (address + 4 - 2049 + 2) bytes)
      next = address + 4 + Array.length text + 1
    in
      if link == 0 then Right lines
      else if link /= next then Left ("line " <> show number <> " links to " <> show link <> ", not to " <> show next)
      else do
        line <- detokenize text
        go link (Array.snoc lines (show number <> " " <> line))
  detokenize text = do
    parts <- traverse part text
    let plain = joinWith "" (map (\b -> if b >= 128 then "_" else character b) text)
    if any (\k -> contains (Pattern k.name) plain) keywords then Left ("a keyword stored as plain letters: " <> plain)
    else Right (joinWith "" parts)
  part b =
    if b >= 128 then maybe (Left ("unknown token " <> show b)) (Right <<< _.name) (Array.find (\k -> k.token == b) keywords)
    else Right (character b)
  character b = maybe "?" CodeUnits.singleton (fromCharCode b)

-- | Valid cells, `columns` × `rows` of them: each cell a random hires
-- | cell, each pixel one of that cell's colors.
genScreen :: Int -> Int -> Gen Screen
genScreen columns rows = do
  cells <- vectorOf rows (vectorOf columns (elements hiresCells))
  image <- Array.concat <$> traverse pixelRows cells
  pure { cells, image }
  where
  -- The 8 pixel rows of one row of cells.
  pixelRows row = vectorOf 8 (Array.concat <$> traverse (\c -> vectorOf 8 (elements (colorsOf c))) row)

-- | A picture made only of valid hires cells, 1 to 3 cells each way.
newtype HiresPicture = HiresPicture (Array (Array RGB))

instance Arbitrary HiresPicture where
  arbitrary = do
    columns <- chooseInt 1 3
    rows <- chooseInt 1 3
    HiresPicture <<< _.image <$> genScreen columns rows

-- | A whole screen of valid cells, 320 × 200 pixels.
newtype FullScreen = FullScreen Screen

instance Arbitrary FullScreen where
  arbitrary = FullScreen <$> genScreen 40 25

spec :: Spec Unit
spec = describe "Puregrain.Machine.C64" do

  describe "hiresCells" do
    it "has the 136 cell palettes hires mode can show, all looking different" do
      Array.length all136 `shouldEqual` 136
      Array.length (Array.nubByEq sameColors all136) `shouldEqual` 136

    it "lists the 16 single colors first, by code, then the pairs, nearest first" do
      let
        singles = Array.takeWhile (\c -> foreground c == background c) all136
        pairs = Array.drop (Array.length singles) all136
        spreads = map (\c -> distance (expectedColor (foreground c)) (expectedColor (background c))) pairs
      map foreground singles `shouldEqual` Array.range 0 15
      Array.filter (\c -> foreground c == background c) pairs `shouldEqual` []
      and (Array.zipWith (<=) spreads (Array.drop 1 spreads)) `shouldEqual` true

    it "puts the darker color, by luma, in the foreground" do
      Array.filter (\c -> luma (expectedColor (foreground c)) > luma (expectedColor (background c))) all136 `shouldEqual` []

    it "uses the C64's colors, Colodore's values, foreground first" do
      let
        expected c =
          if foreground c == background c then NEA.singleton (expectedColor (foreground c))
          else NEA.cons' (expectedColor (foreground c)) [ expectedColor (background c) ]
      Array.filter (\c -> colorsOf c /= expected c) all136 `shouldEqual` []

  describe "hiresScreen" do
    it "is 8x8 cells, with the hires cells in their order and their colors" do
      hiresScreen.size `shouldEqual` { width: 8, height: 8 }
      NEA.toArray hiresScreen.candidates `shouldEqual` all136
      map (cellColors <<< hiresScreen.palette) all136 `shouldEqual` map colorsOf all136

    -- Holds only because of the order: grey, for example, lies on the
    -- line from black to white, so a cell of black and grey fits black
    -- and white perfectly too; the nearer pair must come first, or the
    -- grey pixels would turn into black and white dots.
    it "leaves a picture made only of valid hires cells unchanged, with any kernel and rule" do
      quickCheck \(TestKernel kernel) (TestCellQuantizer rule) (HiresPicture picture) ->
        (ditherCells kernel rule hiresScreen picture).image === picture

  describe "toHiresPrg" do
    it "loads at 2049, where BASIC programs start, with the viewer there: five lines, keywords as tokens" do
      let bytes = toHiresPrg (foregroundAt [])
      map (Array.take 2) bytes `shouldEqual` Right [ 0x01, 0x08 ]
      (bytes >>= listing) `shouldEqual` Right
        [ "10 B=PEEK(53280):D=PEEK(53265):M=PEEK(53272)"
        , "20 POKE 53265,D AND 239:POKE 53280,0:POKE 53272,56:POKE 53265,D OR 32"
        , "30 POKE 198,0"
        , "40 GET K$:IF K$=\"\" THEN 40"
        , "50 POKE 53265,D AND 239:POKE 53272,M:POKE 53280,B:POKE 53265,D"
        ]
      -- The program ends at 2226 with two zero bytes; zeros follow up to
      -- the colors at 3072.
      map (unusual 0 <<< region 2226 3072) bytes `shouldEqual` Right []

    it "stores a BASIC line as the C64 does: the next line's address and the line number, low byte first, the text, a 0" do
      -- Line 30, after line 10 (37 bytes from 2049) and line 20 (56):
      -- the next line at 2154 ($086A), the number 30, POKE as its token,
      -- the rest as characters.
      map (region 2142 2154) (toHiresPrg (foregroundAt []))
        `shouldEqual` Right [ 0x6A, 0x08, 30, 0, 0x97, 0x20, 0x31, 0x39, 0x38, 0x2C, 0x30, 0 ]

    it "puts each pixel at the C64's address: each cell's 8 bytes in a row, the leftmost pixel in the highest bit" do
      let bitmapOf points = map (unusual 0 <<< region 8192 16192) (toHiresPrg (foregroundAt points))
      bitmapOf [ { x: 0, y: 0 } ] `shouldEqual` Right [ { offset: 0, value: 128 } ]
      bitmapOf [ { x: 7, y: 0 } ] `shouldEqual` Right [ { offset: 0, value: 1 } ]
      -- One pixel row down is the next byte, one cell to the right 8
      -- bytes on, and one cell row down 320.
      bitmapOf [ { x: 0, y: 1 } ] `shouldEqual` Right [ { offset: 1, value: 128 } ]
      bitmapOf [ { x: 8, y: 0 } ] `shouldEqual` Right [ { offset: 8, value: 128 } ]
      bitmapOf [ { x: 0, y: 8 } ] `shouldEqual` Right [ { offset: 320, value: 128 } ]
      bitmapOf [ { x: 319, y: 199 } ] `shouldEqual` Right [ { offset: 7999, value: 1 } ]

    it "writes 14,145 bytes, the colors at 3072, foreground x 16 + background, row by row, the bitmap at 8192, zeros between" do
      let
        -- Cell column 2 of cell row 1: blue (the darker) on yellow, all
        -- background.
        special x y = x == 2 && y == 1
        bytes = toHiresPrg $ screenOf (\x y -> if special x y then hiresCell 6 7 else blackOnWhite) \x y ->
          if special (x / 8) (y / 8) then expectedColor 7 else expectedColor 1
      map Array.length bytes `shouldEqual` Right 14145
      map (unusual 1 <<< region 3072 4072) bytes `shouldEqual` Right [ { offset: 40 + 2, value: 6 * 16 + 7 } ]
      map (unusual 0 <<< region 4072 8192) bytes `shouldEqual` Right []
      map (unusual 0 <<< region 8192 16192) bytes `shouldEqual` Right []

    it "gives a single-color cell the bit 0 everywhere, like a pair's background" do
      let
        -- The first cell is white alone, with white pixels; all the
        -- others are black on white, with black (foreground) pixels.
        bytes = toHiresPrg $ screenOf (\x y -> if x == 0 && y == 0 then hiresCell 1 1 else blackOnWhite) \x y ->
          if x < 8 && y < 8 then expectedColor 1 else expectedColor 0
      map (unusual 255 <<< region 8192 16192) bytes `shouldEqual` Right (map (\row -> { offset: row, value: 0 }) (Array.range 0 7))

    it "can be read back: an independent reader gives the same cells and pixels, for any valid screen" do
      -- 10 screens instead of 100: each has 64,000 pixels.
      quickCheck' 10 \(FullScreen s) -> case toHiresPrg s of
        Left message -> Failed message
        Right bytes ->
          let
            decoded = readPrg bytes
          in
            if Array.length bytes /= 14145 then Failed ("got " <> show (Array.length bytes) <> " bytes, not 14145")
            else if decoded.cells /= map (map codesOf) s.cells then Failed "the cells read back differ"
            else if decoded.image /= s.image then Failed "the pixels read back differ"
            else Success

    it "rejects an image that isn't 320x200, cells that don't match it, and a pixel that isn't one of its cell's colors" do
      let
        valid = foregroundAt []
        failure = either Just (const Nothing) <<< toHiresPrg
      failure (valid { image = map (Array.drop 1) valid.image }) `shouldSatisfy` mentions "the image must be 320x200, a C64 hires screen; it's 319x200"
      failure (valid { image = Array.drop 1 valid.image }) `shouldSatisfy` mentions "it's 320x199"
      failure (valid { cells = map (Array.drop 1) valid.cells }) `shouldSatisfy` mentions "the cells must form a 40x25 grid, one per 8x8 cell of the image; they're 39x25"
      -- Red in a cell of black and white.
      failure (screenOf (\_ _ -> blackOnWhite) \x y -> if x == 3 && y == 5 then expectedColor 2 else expectedColor 1)
        `shouldSatisfy` mentions "pixel (3, 5) isn't one of its cell's colors"

  describe "toArtStudio" do
    it "writes 9009 bytes: the load address 8192, the bitmap and the colors as in the .prg, then 7 zeros" do
      let
        -- Cell column 2 of cell row 1 blue on yellow, all background; the
        -- others black on white, with one black pixel at (0, 0).
        special x y = x == 2 && y == 1
        screen = screenOf (\x y -> if special x y then hiresCell 6 7 else blackOnWhite) \x y ->
          if special (x / 8) (y / 8) then expectedColor 7 else if x == 0 && y == 0 then expectedColor 0 else expectedColor 1
        art = toArtStudio screen
        prg = toHiresPrg screen
      map Array.length art `shouldEqual` Right 9009
      map (Array.take 2) art `shouldEqual` Right [ 0x00, 0x20 ]
      -- Compared as a whole: a failure would print thousands of numbers
      -- otherwise.
      (map (Array.slice 2 8002) art == map (region 8192 16192) prg) `shouldEqual` true
      (map (Array.slice 8002 9002) art == map (region 3072 4072) prg) `shouldEqual` true
      map (Array.drop 9002) art `shouldEqual` Right [ 0, 0, 0, 0, 0, 0, 0 ]

    it "can be read back as RECOIL reads it: the same cells and pixels, for any valid screen" do
      -- 10 screens instead of 100: each has 64,000 pixels.
      quickCheck' 10 \(FullScreen s) -> case toArtStudio s of
        Left message -> Failed message
        Right bytes ->
          let
            decoded = readArt bytes
          in
            if Array.length bytes /= 9009 then Failed ("got " <> show (Array.length bytes) <> " bytes, not 9009")
            else if decoded.cells /= map (map codesOf) s.cells then Failed "the cells read back differ"
            else if decoded.image /= s.image then Failed "the pixels read back differ"
            else Success

    it "rejects what toHiresPrg rejects, naming itself" do
      let
        valid = foregroundAt []
        failure = either Just (const Nothing) <<< toArtStudio
      failure (valid { image = Array.drop 1 valid.image }) `shouldSatisfy` mentions "toArtStudio: the image must be 320x200, a C64 hires screen; it's 320x199"
      failure (valid { cells = map (Array.drop 1) valid.cells }) `shouldSatisfy` mentions "toArtStudio: the cells must form a 40x25 grid"
      failure (screenOf (\_ _ -> blackOnWhite) \x y -> if x == 3 && y == 5 then expectedColor 2 else expectedColor 1)
        `shouldSatisfy` mentions "toArtStudio: pixel (3, 5) isn't one of its cell's colors"
