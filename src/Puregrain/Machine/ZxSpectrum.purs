-- | The ZX Spectrum's screen: 8 × 8 cells, each with two colors, an ink
-- | and a paper, from the machine's 8 colors, plus one BRIGHT bit for both.
-- | With `Puregrain.Cells`, that gives images the Spectrum could show:
-- |
-- | ```purescript
-- | import Puregrain.Cells (ditherCells, nearestInCell, orderedInCell)
-- | import Puregrain.Machine.ZxSpectrum as Zx
-- |
-- | -- ordered dithering inside the cells, with a threshold map m
-- | { cells, image } = ditherCells noDiffusion (orderedInCell m) Zx.screen picture
-- |
-- | -- error diffusion inside the cells
-- | { cells, image } = ditherCells atkinson nearestInCell Zx.screen picture
-- | ```
-- |
-- | Ordered dithering, with the 8 × 8 Bayer map, looks most like the
-- | Spectrum's own art and keeps every tone; with error diffusion,
-- | Atkinson looks best.
-- |
-- | `cells` holds each cell's `Attribute`: its ink, paper and BRIGHT, as a
-- | screen file needs them; `toScr` turns the whole result into one. The
-- | colors are those of `Puregrain.Palette.Presets.zxSpectrum`. The
-- | colors, the attributes and the file layouts in full:
-- | [docs/machine-screens/zx-spectrum.md](https://github.com/roman-mkh/puregrain/blob/master/docs/machine-screens/zx-spectrum.md).
module Puregrain.Machine.ZxSpectrum
  ( Attribute
  , ink
  , paper
  , bright
  , attributes
  , attributePalette
  , screen
  , toScr
  , toTap
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Char (toCharCode)
import Data.Either (Either(..))
import Data.Foldable (all, foldM, foldl)
import Data.Int.Bits (shr, xor, (.&.))
import Data.Maybe (maybe)
import Data.String.CodeUnits (toCharArray)
import Data.Traversable (traverse)
import Partial.Unsafe (unsafePartial)
import Puregrain.Cells (CellMode, CellPalette, colorPair, singleColor)
import Puregrain.Palette (distance2)
import Puregrain.Palette.Presets (zxSpectrum)
import Puregrain.Pixel (RGB)

-- | One cell's attribute: its ink and paper, as ZX color codes (0 black,
-- | 1 blue, 2 red, 3 magenta, 4 green, 5 cyan, 6 yellow, 7 white), and
-- | whether BRIGHT is set. Only the 71 values in `attributes` exist.
newtype Attribute = Attribute { ink :: Int, paper :: Int, bright :: Boolean }

derive instance Eq Attribute
derive newtype instance Show Attribute

-- | The ink's color code, 0 to 7.
ink :: Attribute -> Int
ink (Attribute a) = a.ink

-- | The paper's color code, 0 to 7.
paper :: Attribute -> Int
paper (Attribute a) = a.paper

-- | Whether BRIGHT is set, for both ink and paper.
bright :: Attribute -> Boolean
bright (Attribute a) = a.bright

-- | Every attribute that looks different: per brightness, 8 cells of a
-- | single color and 28 pairs, 72 in all, minus one, because all black
-- | looks the same with and without BRIGHT (it's listed once, without).
-- | Ink is the darker color, the lower code, and paper the lighter, as in
-- | the Spectrum's default of black ink on white paper; a single-color
-- | cell has ink = paper.
-- |
-- | They're listed in the order `Puregrain.Cells` tries them, where the
-- | earlier wins a tie: the single colors first, then the pairs by the
-- | distance between their two colors, nearest first (at equal distances,
-- | normal before bright, then by ink, then by paper). A cell that several
-- | palettes fit equally well thus gets the narrowest, the calmest.
attributes :: NonEmptyArray Attribute
attributes = NEA.appendArray normalSingles (brightSingles <> pairs)
  where
  attribute i p b = Attribute { ink: i, paper: p, bright: b }
  normalSingles = map (\c -> attribute c c false) (NEA.range 0 7)
  brightSingles = map (\c -> attribute c c true) (Array.range 1 7)
  pairs = Array.sortBy nearestFirst do
    b <- [ false, true ]
    i <- Array.range 0 6
    p <- Array.range (i + 1) 7
    pure (attribute i p b)
  nearestFirst x y =
    compare (spread x) (spread y) <> compare (bright x) (bright y) <> compare (ink x) (ink y)
      <> compare (paper x) (paper y)
  spread (Attribute a) = distance2 (color a.bright a.ink) (color a.bright a.paper)

-- | The attribute's colors, for `Puregrain.Cells`: the ink, then the
-- | paper, or the one color of a single-color cell. With `orderedInCell`,
-- | the order means that a cell is ink with paper dots added as a pixel
-- | nears the paper.
attributePalette :: Attribute -> CellPalette
attributePalette (Attribute a) =
  if a.ink == a.paper then singleColor (color a.bright a.ink)
  else colorPair (color a.bright a.ink) (color a.bright a.paper)

-- | The Spectrum's screen mode, for `Puregrain.Cells`: cells of 8 × 8
-- | pixels, each using one of the `attributes`, tried in their order, with
-- | `attributePalette`'s colors.
screen :: CellMode Attribute
screen = { size: { width: 8, height: 8 }, palette: attributePalette, candidates: attributes }

-- | A dithered screen as a `.scr` file: the 6912 bytes of the Spectrum's
-- | screen memory, as `SAVE "name" SCREEN$` saves them, and as many
-- | emulators and tools open them.
-- |
-- | - `{ cells, image }`: what `Puregrain.Cells.ditherCells` returns with
-- |   this module's `screen`, for a 256 × 192 picture.
-- |
-- | ```purescript
-- | bytes = toScr (ditherCells noDiffusion (orderedInCell m) screen picture)
-- | ```
-- |
-- | The first 6144 bytes are the bitmap, one bit per pixel (1 for the ink,
-- | 0 for the paper, the leftmost pixel in the highest bit), its rows in the
-- | Spectrum's interleaved order. Then come 768 attribute bytes, one per
-- | cell, row by row: BRIGHT × 64 + paper × 8 + ink, with FLASH off. A
-- | single-color cell has all its bits 0.
-- |
-- | `Left`, with a message, for an image that isn't 256 × 192, for cells
-- | that don't form the matching 32 × 24 grid, or for a pixel that isn't
-- | one of its cell's colors: then the cells weren't chosen for this image.
toScr :: { cells :: Array (Array Attribute), image :: Array (Array RGB) } -> Either String (Array Int)
toScr { cells, image } =
  -- The sizes are checked before anything reads the arrays by index.
  if not (isGrid 256 192 image) then
    Left ("toScr: the image must be 256x192, a ZX Spectrum screen; it's " <> sizeOf image)
  else if not (isGrid 32 24 cells) then
    Left ("toScr: the cells must form a 32x24 grid, one per 8x8 cell of the image; they're " <> sizeOf cells)
  else
    (_ <> map attributeByte (Array.concat cells)) <$> traverse (bitmapByte cells image) (Array.range 0 6143)

-- | Whether the rows form a grid of exactly `width` × `height`.
isGrid :: forall a. Int -> Int -> Array (Array a) -> Boolean
isGrid width height rows = Array.length rows == height && Array.all (\row -> Array.length row == width) rows

-- | "width x height", or, for rows of different lengths, how many rows.
sizeOf :: forall a. Array (Array a) -> String
sizeOf rows =
  if Array.all (\row -> Array.length row == width) rows then show width <> "x" <> show (Array.length rows)
  else show (Array.length rows) <> " rows of different lengths"
  where
  width = maybe 0 Array.length (Array.head rows)

-- | The bitmap byte at offset `o`: 8 pixels of one row. The Spectrum
-- | interleaves the rows: from high to low, the offset's bits give the
-- | screen third (64 rows each), the pixel row within the cell, the cell
-- | row within the third, and the byte's column (0 to 31).
bitmapByte :: Array (Array Attribute) -> Array (Array RGB) -> Int -> Either String Int
bitmapByte cells image o = foldM (\byte i -> (\b -> byte * 2 + b) <$> inkBit (column * 8 + i)) 0 (Array.range 0 7)
  where
  column = o .&. 31
  y = (shr o 11 .&. 3) * 64 + (shr o 5 .&. 7) * 8 + (shr o 8 .&. 7)
  -- Safe: `toScr` checked both grids before calling this.
  at :: forall a. Array (Array a) -> Int -> Int -> a
  at rows r c = unsafePartial (Array.unsafeIndex (Array.unsafeIndex rows r) c)
  inkBit x = pixelBit (at cells (y / 8) column) x y (at image y x)

-- | 1 for the cell's ink, 0 for its paper. Paper is tried first, so a
-- | single-color cell (ink = paper) gets 0 everywhere.
pixelBit :: Attribute -> Int -> Int -> RGB -> Either String Int
pixelBit (Attribute a) x y pixel =
  if pixel == color a.bright a.paper then Right 0
  else if pixel == color a.bright a.ink then Right 1
  else Left ("toScr: pixel (" <> show x <> ", " <> show y <> ") isn't one of its cell's colors; were the cells chosen for this image?")

-- | BRIGHT × 64 + paper × 8 + ink; FLASH (128) stays off.
attributeByte :: Attribute -> Int
attributeByte (Attribute a) = (if a.bright then 64 else 0) + a.paper * 8 + a.ink

-- | A dithered screen as a `.tap` tape image: a short BASIC program that
-- | starts by itself and loads the screen, then the screen as a CODE file.
-- | Open it in an emulator, or type `LOAD ""` on a Spectrum: the picture
-- | appears and stays until a key is pressed.
-- |
-- | - `String`: the name on the tape, up to 10 printable ASCII characters.
-- | - `{ cells, image }`: as for `toScr`.
-- |
-- | ```purescript
-- | bytes = toTap "sphere" (ditherCells noDiffusion (orderedInCell m) screen picture)
-- | ```
-- |
-- | `Left`, with a message, for a name that's too long or holds other
-- | characters, and as `toScr` for the screen. The tape format:
-- | https://worldofspectrum.net/zx-modules/fileformats/tapformat.html
toTap :: String -> { cells :: Array (Array Attribute), image :: Array (Array RGB) } -> Either String (Array Int)
toTap name dithered = do
  nameBytes <- tapeName name
  bytes <- toScr dithered
  pure
    ( tapeFile { kind: 0, name: nameBytes, param1: 10, param2: Array.length loader } loader
        <> tapeFile { kind: 3, name: nameBytes, param1: 16384, param2: 32768 } bytes
    )

-- The tape format (worldofspectrum.net/zx-modules/fileformats/tapformat.html,
-- formats.kaitai.io/zx_spectrum_tap/): a sequence of blocks, each a
-- two-byte length, then that many bytes: a flag (0 for a header, 255 for
-- data), the bytes, and a checksum, the XOR of the flag and the bytes. A
-- file is a header block, then a data block. The header's bytes: the type
-- (0 a BASIC program, 3 bytes), the name in 10 bytes padded with spaces,
-- the data's length, and two parameters: for a program, the line it
-- starts at and its length; for bytes, the start address (16384 for the
-- screen) and 32768.

-- | One file on tape: its header block, then its data block.
tapeFile :: { kind :: Int, name :: Array Int, param1 :: Int, param2 :: Int } -> Array Int -> Array Int
tapeFile h bytes =
  tapeBlock 0 ([ h.kind ] <> h.name <> word (Array.length bytes) <> word h.param1 <> word h.param2)
    <> tapeBlock 255 bytes

-- | One tape block: its length, the flag, the bytes, the checksum.
tapeBlock :: Int -> Array Int -> Array Int
tapeBlock flag bytes = word (Array.length bytes + 2) <> [ flag ] <> bytes <> [ foldl xor flag bytes ]

-- | A two-byte number as the Z80 stores it, less significant byte first.
word :: Int -> Array Int
word n = [ n .&. 255, shr n 8 .&. 255 ]

-- | The name's character codes, padded with spaces to 10.
tapeName :: String -> Either String (Array Int)
tapeName name =
  if Array.length codes > 10 then
    Left ("toTap: a tape name has at most 10 characters; \"" <> name <> "\" has " <> show (Array.length codes))
  else if not (all (\c -> c >= 32 && c <= 126) codes) then
    Left ("toTap: a tape name may hold only printable ASCII characters, codes 32 to 126; \"" <> name <> "\" has others")
  else
    Right (codes <> Array.replicate (10 - Array.length codes) 32)
  where
  codes = map toCharCode (toCharArray name)

-- | The BASIC loader, `10 LOAD "" SCREEN$: PAUSE 0`, as the Spectrum
-- | stores a program line (the ZX Spectrum manual, chapter 24): the line
-- | number, more significant byte first; the length of the rest, less
-- | significant first; the text, with each keyword one character (LOAD
-- | 0xEF, SCREEN$ 0xAA, PAUSE 0xF2; en.wikipedia.org/wiki/
-- | ZX_Spectrum_character_set), and the number 0 as its digit, then 0x0E
-- | and its five-byte form, all zeros; ENTER, 0x0D.
loader :: Array Int
loader = [ 0, 10 ] <> word (Array.length text) <> text
  where
  text = [ 0xEF, 0x22, 0x22, 0xAA, 0x3A, 0xF2, 0x30, 0x0E, 0, 0, 0, 0, 0, 0x0D ]

-- | A color code's color at a brightness, from the `zxSpectrum` preset:
-- | its first 8 colors are codes 0 to 7 at normal brightness, the next 7
-- | codes 1 to 7 with BRIGHT set; bright black is black.
color :: Boolean -> Int -> RGB
color isBright code =
  unsafePartial (NEA.unsafeIndex zxSpectrum (if isBright && code > 0 then 7 + code else code))
