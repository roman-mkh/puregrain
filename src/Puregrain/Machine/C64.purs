-- | The Commodore 64's hires bitmap screen: 320 × 200 pixels in cells of
-- | 8 × 8, each cell with two of the machine's 16 colors, a foreground and
-- | a background, chosen freely. With `Puregrain.Cells`, that gives
-- | pictures the C64 could show:
-- |
-- | ```purescript
-- | import Puregrain.Cells (ditherCells, nearestInCell, orderedInCell)
-- | import Puregrain.Machine.C64 as C64
-- |
-- | -- ordered dithering inside the cells, with a threshold map m
-- | { cells, image } = ditherCells noDiffusion (orderedInCell m) C64.hiresScreen picture
-- |
-- | -- error diffusion inside the cells
-- | { cells, image } = ditherCells atkinson nearestInCell C64.hiresScreen picture
-- | ```
-- |
-- | `cells` holds each cell's `HiresCell`: its foreground and background,
-- | as the machine's screen memory needs them; `toHiresPrg` turns the
-- | whole result into a C64 program that shows it. The colors are those of
-- | `Puregrain.Palette.Presets.c64`. The C64's multicolor mode isn't
-- | supported yet.
module Puregrain.Machine.C64
  ( HiresCell
  , foreground
  , background
  , hiresCells
  , hiresPalette
  , hiresScreen
  , toHiresPrg
  ) where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Char (toCharCode)
import Data.Either (Either(..))
import Data.Foldable (foldM)
import Data.Int.Bits (shr, (.&.))
import Data.Maybe (Maybe(..))
import Data.String.CodeUnits (toCharArray)
import Data.Traversable (traverse)
import Partial.Unsafe (unsafePartial)
import Puregrain.Cells (CellMode, CellPalette, colorPair, singleColor)
import Puregrain.Internal.Util (isGrid, sizeOf)
import Puregrain.Palette (distance2)
import Puregrain.Palette.Presets (c64)
import Puregrain.Pixel (RGB(..))

-- | One hires cell's colors: the foreground, the color of the cell's 1
-- | bits, and the background, the color of its 0 bits, as C64 color codes
-- | (0 black, 1 white, 2 red, 3 cyan, 4 purple, 5 green, 6 blue, 7 yellow,
-- | 8 orange, 9 brown, 10 light red, 11 dark grey, 12 grey, 13 light
-- | green, 14 light blue, 15 light grey). Only the 136 values in
-- | `hiresCells` exist.
newtype HiresCell = HiresCell { foreground :: Int, background :: Int }

derive instance Eq HiresCell
derive newtype instance Show HiresCell

-- | The foreground's color code, 0 to 15: the color of the cell's 1 bits.
foreground :: HiresCell -> Int
foreground (HiresCell c) = c.foreground

-- | The background's color code, 0 to 15: the color of the cell's 0 bits.
background :: HiresCell -> Int
background (HiresCell c) = c.background

-- | Every hires cell that looks different: the 16 single colors and the
-- | 120 pairs, 136 in all. In a pair, the foreground is the darker color
-- | and the background the lighter, as with the ZX Spectrum's black ink on
-- | white paper. Darker means a lower luma, 0.299 R + 0.587 G + 0.114 B,
-- | since the C64's color codes aren't in order of brightness. A
-- | single-color cell has foreground = background.
-- |
-- | They're listed in the order `Puregrain.Cells` tries them, where the
-- | earlier wins a tie: the single colors first, by code, then the pairs by
-- | the distance between their two colors, nearest first (at equal
-- | distances, by foreground, then by background). A cell that several
-- | palettes fit equally well thus gets the narrowest, the calmest.
hiresCells :: NonEmptyArray HiresCell
hiresCells = NEA.appendArray singles pairs
  where
  singles = map (\c -> HiresCell { foreground: c, background: c }) (NEA.range 0 15)
  pairs = Array.sortBy nearestFirst do
    a <- Array.range 0 14
    b <- Array.range (a + 1) 15
    -- On exactly equal luma, the lower code is the foreground.
    pure
      if luma (color a) <= luma (color b) then HiresCell { foreground: a, background: b }
      else HiresCell { foreground: b, background: a }
  nearestFirst x y =
    compare (spread x) (spread y) <> compare (foreground x) (foreground y)
      <> compare (background x) (background y)
  spread c = distance2 (color (foreground c)) (color (background c))

-- | The cell's colors, for `Puregrain.Cells`: the foreground, then the
-- | background, or the one color of a single-color cell. With
-- | `orderedInCell`, the order means that a cell is foreground, with
-- | background dots added as a pixel nears the background.
hiresPalette :: HiresCell -> CellPalette
hiresPalette (HiresCell c) =
  if c.foreground == c.background then singleColor (color c.foreground)
  else colorPair (color c.foreground) (color c.background)

-- | The C64's hires screen mode, for `Puregrain.Cells`: cells of 8 × 8
-- | pixels, each using one of the `hiresCells`, tried in their order, with
-- | `hiresPalette`'s colors.
hiresScreen :: CellMode HiresCell
hiresScreen = { size: { width: 8, height: 8 }, palette: hiresPalette, candidates: hiresCells }

-- | A dithered hires screen as a `.prg` file: a C64 program that shows the
-- | picture by itself. Open it in an emulator, which starts it, or load
-- | and run it on a C64 (`LOAD "name",8` and `RUN`). The picture stays
-- | until a key is pressed; then the screen is as it was.
-- |
-- | - `{ cells, image }`: what `Puregrain.Cells.ditherCells` returns with
-- |   this module's `hiresScreen`, for a 320 × 200 picture.
-- |
-- | ```purescript
-- | bytes = toHiresPrg (ditherCells noDiffusion (orderedInCell m) hiresScreen picture)
-- | ```
-- |
-- | The file is 14,145 bytes: the address it loads at, 2049 ($0801), where
-- | BASIC programs start, and from there a short BASIC program, the
-- | viewer; the cells' colors at 3072 ($0C00), one byte per cell, row by
-- | row: foreground × 16 + background; and the bitmap at 8192 ($2000), one
-- | bit per pixel (1 for the foreground, 0 for the background, the
-- | leftmost pixel in the highest bit), each cell's 8 bytes in a row, the
-- | cells row by row. Zeros fill the gaps. A single-color cell has all its
-- | bits 0. The viewer points the video chip at the colors and the bitmap
-- | where they are, with a black border, and puts everything back after a
-- | key.
-- |
-- | `Left`, with a message, for an image that isn't 320 × 200, for cells
-- | that don't form the matching 40 × 25 grid, or for a pixel that isn't
-- | one of its cell's colors: then the cells weren't chosen for this image.
toHiresPrg :: { cells :: Array (Array HiresCell), image :: Array (Array RGB) } -> Either String (Array Int)
toHiresPrg { cells, image } =
  -- The sizes are checked before anything reads the arrays by index.
  if not (isGrid 320 200 image) then
    Left ("toHiresPrg: the image must be 320x200, a C64 hires screen; it's " <> sizeOf image)
  else if not (isGrid 40 25 cells) then
    Left ("toHiresPrg: the cells must form a 40x25 grid, one per 8x8 cell of the image; they're " <> sizeOf cells)
  else do
    bitmap <- traverse (bitmapByte cells image) (Array.range 0 7999)
    -- Each part at its address, zeros up to the next.
    pure
      ( word basicStart
          <> padTo (colorsStart - basicStart) viewer
          <> padTo (bitmapStart - colorsStart) (map colorByte (Array.concat cells))
          <> bitmap
      )
  where
  padTo n bytes = bytes <> Array.replicate (n - Array.length bytes) 0

-- | Where the file's parts go in the C64's memory: BASIC programs start at
-- | 2049. The video chip finds the colors and the bitmap where 53272 says,
-- | in steps of 1024 and 8192 (C64-Wiki: 53272); the viewer sets it to
-- | 3 × 16 + 8 = 56 for these two. Both lie outside 4096 to 8191, where
-- | the video chip sees the character ROM instead of RAM (C64-Wiki: VIC
-- | bank).
basicStart :: Int
basicStart = 0x0801

colorsStart :: Int
colorsStart = 0x0C00

bitmapStart :: Int
bitmapStart = 0x2000

-- | The bitmap byte at offset `o`: 8 pixels of one row of one cell. The
-- | cells come row by row, 40 to a row of cells, each as 8 bytes, its top
-- | pixel row first.
bitmapByte :: Array (Array HiresCell) -> Array (Array RGB) -> Int -> Either String Int
bitmapByte cells image o = foldM (\byte i -> (\b -> byte * 2 + b) <$> foregroundBit (column * 8 + i)) 0 (Array.range 0 7)
  where
  column = (o / 8) `mod` 40
  y = (o / 320) * 8 + o `mod` 8
  -- Safe: `toHiresPrg` checked both grids before calling this.
  at :: forall a. Array (Array a) -> Int -> Int -> a
  at rows r c = unsafePartial (Array.unsafeIndex (Array.unsafeIndex rows r) c)
  foregroundBit x = pixelBit (at cells (y / 8) column) x y (at image y x)

-- | 1 for the cell's foreground, 0 for its background. The background is
-- | tried first, so a single-color cell gets 0 everywhere.
pixelBit :: HiresCell -> Int -> Int -> RGB -> Either String Int
pixelBit (HiresCell c) x y pixel =
  if pixel == color c.background then Right 0
  else if pixel == color c.foreground then Right 1
  else Left ("toHiresPrg: pixel (" <> show x <> ", " <> show y <> ") isn't one of its cell's colors; were the cells chosen for this image?")

-- | A cell's byte for the video chip: the foreground, the color of the 1
-- | bits, in the upper half; the background in the lower.
colorByte :: HiresCell -> Int
colorByte (HiresCell c) = c.foreground * 16 + c.background

-- | A two-byte number as the 6502 stores it, less significant byte first.
word :: Int -> Array Int
word n = [ n .&. 255, shr n 8 .&. 255 ]

-- | The viewer, a BASIC program, as the C64 stores it:
-- |
-- | ```
-- | 10 B=PEEK(53280):D=PEEK(53265):M=PEEK(53272)
-- | 20 POKE 53265,D AND 239:POKE 53280,0:POKE 53272,56:POKE 53265,D OR 32
-- | 30 POKE 198,0
-- | 40 GET K$:IF K$="" THEN 40
-- | 50 POKE 53265,D AND 239:POKE 53272,M:POKE 53280,B:POKE 53265,D
-- | ```
-- |
-- | Line 10 notes the border color (53280) and the video chip's two
-- | registers (53265, 53272), to put them back at the end. Line 20 blanks
-- | the screen (bit 4 of 53265 off), so nothing half-set shows; makes the
-- | border black; points the video chip at the colors and the bitmap
-- | (53272); then turns bitmap mode on (bit 5) and the screen back on.
-- | Line 30 empties the keyboard buffer (198 counts the keys in it), so a
-- | key pressed while loading doesn't end the picture at once; line 40
-- | waits for a key. Line 50 blanks the screen again, puts the registers
-- | and the border back, and shows the text screen, which the viewer never
-- | changed.
viewer :: Array Int
viewer = program basicStart
  [ { number: 10, text: t "B" <> equals <> peek <> t "(53280):D" <> equals <> peek <> t "(53265):M" <> equals <> peek <> t "(53272)" }
  , { number: 20, text: poke <> t " 53265,D " <> and_ <> t " 239:" <> poke <> t " 53280,0:" <> poke <> t " 53272,56:" <> poke <> t " 53265,D " <> or_ <> t " 32" }
  , { number: 30, text: poke <> t " 198,0" }
  , { number: 40, text: get <> t " K$:" <> if_ <> t " K$" <> equals <> t "\"\" " <> then_ <> t " 40" }
  , { number: 50, text: poke <> t " 53265,D " <> and_ <> t " 239:" <> poke <> t " 53272,M:" <> poke <> t " 53280,B:" <> poke <> t " 53265,D" }
  ]
  where
  -- Each keyword is stored as one byte, its token (C64-Wiki: BASIC
  -- token); everything else as its character's code, the same as ASCII
  -- for these characters.
  t = map toCharCode <<< toCharArray
  peek = [ 0xC2 ]
  poke = [ 0x97 ]
  and_ = [ 0xAF ]
  or_ = [ 0xB0 ]
  get = [ 0xA1 ]
  if_ = [ 0x8B ]
  then_ = [ 0xA7 ]
  equals = [ 0xB2 ]

-- | BASIC lines as the C64 stores them from the address `start` on
-- | (C64-Wiki: BASIC token): each line the address of the next line and
-- | its number, both low byte first, then its text and a 0; two zero
-- | bytes end the program.
program :: Int -> Array { number :: Int, text :: Array Int } -> Array Int
program start lines = case Array.uncons lines of
  Nothing -> [ 0, 0 ]
  Just { head, tail } ->
    let
      next = start + 4 + Array.length head.text + 1
    in
      word next <> word head.number <> head.text <> [ 0 ] <> program next tail

-- | A color code's color, from the `c64` preset, which lists the colors in
-- | code order.
color :: Int -> RGB
color code = unsafePartial (NEA.unsafeIndex c64 code)

-- | A color's brightness as luma: 0.299 R + 0.587 G + 0.114 B.
luma :: RGB -> Number
luma (RGB p) = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
