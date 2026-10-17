# ZX Spectrum

The ZX Spectrum (Sinclair, 1982) shows 256×192 pixels in cells of 8×8, 32
across and 24 down. Each cell has two colors, an *ink* and a *paper*, from
the machine's 8 colors, and one BRIGHT bit for both, so a cell's two colors
are both normal or both bright. A cell's colors are stored in one
*attribute* byte, hence the name of the effect where colors meet:
attribute clash.

How dithering to cells works in general, and which mode suits which
picture: [README.md](README.md).

## Quick start

```bash
# ordered dithering inside the cells: the classic look
npm run dither-cli -- picture.png screen.png --machine zx-spectrum --bayer 8

# error diffusion inside the cells, for photos with fine detail
npm run dither-cli -- picture.png screen.png --machine zx-spectrum --kernel atkinson

# normal brightness only: no BRIGHT, so large light areas stay even
npm run dither-cli -- picture.png screen.png --machine zx-spectrum --machine-palette normal --bayer 8

# the Spectrum's own files: a screen file, and a tape that loads and shows it
npm run dither-cli -- picture.png screen.scr --machine zx-spectrum --bayer 8
npm run dither-cli -- picture.png screen.tap --machine zx-spectrum --bayer 8
```

The `.scr` and `.tap` files need a picture of exactly 256×192 (see
[Size](README.md#size)). In the library, the module is
`Puregrain.Machine.ZxSpectrum`, imported as `Zx`: `Zx.screen` is the screen
mode for `Puregrain.Cells`, and `Zx.toScr` and `Zx.toTap` write the files.

```purescript
case bayer 8 of
  Just m -> Zx.toTap "sphere" (ditherCells noDiffusion (orderedInCell m) Zx.screen picture)
  Nothing -> Left "no 8 × 8 Bayer map"   -- not reached: 8 is a power of 2
```

## Colors

| Code | Color | Normal | BRIGHT |
|---:|---|---|---|
| 0 | black | `#000000` | `#000000` |
| 1 | blue | `#0000D8` | `#0000FF` |
| 2 | red | `#D80000` | `#FF0000` |
| 3 | magenta | `#D800D8` | `#FF00FF` |
| 4 | green | `#00D800` | `#00FF00` |
| 5 | cyan | `#00D8D8` | `#00FFFF` |
| 6 | yellow | `#D8D800` | `#FFFF00` |
| 7 | white | `#D8D8D8` | `#FFFFFF` |

A code's bits are its channels: 1 blue, 2 red, 4 green. Normal brightness
is `0xD8` = 216, about 85% of bright, the common model: the real colors
were never measured, and emulators also use `0xD7` or `0xCD`. Bright black
is black, so there are 15 distinct colors. They're also a palette of their
own, for colors without the cells: `zxSpectrum` in the library, `--palette
zx15` on the command line (see [palettes.md](../palettes.md)).

## The attributes

Every pair of an ink and a paper, both normal or both bright, and every
single color: per brightness 8 single colors and 28 pairs, 72 in all,
minus one, because all black looks the same with and without BRIGHT. That
makes **71 attributes** that look different, the candidates for each cell
(`Zx.attributes`).

- **Ink and paper:** the ink is the darker color, the lower code, as in the
  Spectrum's default of black ink on white paper. A single-color cell has
  ink = paper.
- **Order:** the 15 single colors first, then the pairs by the distance
  between their two colors, nearest first; at equal distances, normal
  before bright, then by ink, then by paper. On a tie the earlier wins, so
  a cell that several attributes fit equally well gets the narrowest, the
  calmest.
- **Why the order matters:** a picture made only of valid cells must come
  back unchanged. Normal white lies on the line from black to bright
  white, so a cell of black and normal white fits both pairs perfectly;
  only the nearer pair, listed first, keeps it as it was.
- **With ordered dithering,** the ink is the pattern's base: a cell is ink,
  with paper dots added as a pixel nears the paper.
- **One brightness only:** `Zx.normalScreen` offers the 36 attributes
  without BRIGHT, and `Zx.brightScreen` black and the 35 with BRIGHT, both
  in the usual order; on the command line, `--machine-palette normal` or
  `bright`. With normal only, neighbouring cells never switch between
  normal and BRIGHT, so large light areas, skin or sky, say, stay even,
  and the picture is calmer, its colors less vivid. Bright only suits
  vivid pictures: logos, cartoons, strong colors.

## The screen file: .scr

A `.scr` file is the Spectrum's screen memory: 6912 bytes, as
`SAVE "name" SCREEN$` saves them. Many emulators and viewers open it; in
Fuse, with File → Open SCR Screenshot.

- **The bitmap, bytes 0 to 6143:** one bit per pixel, 1 for the ink and 0
  for the paper, the leftmost pixel in the highest bit, 32 bytes per pixel
  row. The rows are interleaved, as in the machine. The byte of the pixel
  at (x, y), with integer division:

  ```
  2048 × (y / 64) + 256 × (y mod 8) + 32 × ((y / 8) mod 8) + x / 8
  ```

  That's the screen's third (64 rows each), the pixel row inside its cell,
  the cell row inside the third, and the column. A single-color cell has
  all its bits 0.
- **The attributes, bytes 6144 to 6911:** one byte per cell, row by row:
  BRIGHT × 64 + paper × 8 + ink. FLASH, 128, stays off.

## The tape: .tap

A `.tap` file is a tape: 6980 bytes that load and show the picture by
themselves.

- **What's on it:** a BASIC program of one line, which starts by itself,

  ```
  10 LOAD "" SCREEN$: PAUSE 0
  ```

  then the screen as a CODE file of 6912 bytes for address 16384, the
  screen memory. The program loads the screen, and `PAUSE 0` keeps it
  until a key is pressed.
- **Loading it:** open it in an emulator, which loads a tape by itself:
  Fuse with File → Open, or [JSSpeccy 3](https://jsspeccy.zxdemo.org/) in
  the browser. On a Spectrum, type `LOAD ""`.
- **The name:** both files on the tape carry a name of up to 10 printable
  ASCII characters. The command line takes the output file's name, without
  its directory and extension, cut to 10.
- **Layout:** each file is two blocks, a header and its data. A block is a
  two-byte length, low byte first, then a flag (0 for a header, 255 for
  data), the bytes, and a checksum, the XOR of the flag and the bytes. A
  header's bytes are the file type (0 a program, 3 bytes), the name padded
  with spaces to 10, the data's length, and two parameters: for the
  program, the line it starts at, 10, and its length; for the screen, the
  address 16384, and 32768.
- **The BASIC line** is stored as the Spectrum stores lines: the line
  number, high byte first; the length of the rest; the text, with each
  keyword one character (`LOAD` 0xEF, `SCREEN$` 0xAA, `PAUSE` 0xF2); the
  number 0 as its digit, followed by 0x0E and its five-byte form, all
  zeros; and ENTER, 0x0D.

## Sources

The values and layouts here were checked against these sources, not
recalled, and the `.tap` was checked by loading it in JSSpeccy 3.

- **Colors:** the 85% rule from [Wikipedia: ZX Spectrum graphic
  modes](https://en.wikipedia.org/wiki/ZX_Spectrum_graphic_modes); the
  values as [lospec](https://lospec.com/palette-list/zx-spectrum).
- **Screen memory:** the address bits and the attribute byte from
  [Wikipedia: ZX Spectrum graphic
  modes](https://en.wikipedia.org/wiki/ZX_Spectrum_graphic_modes); ink 1,
  paper 0, and the row order from the [ZX Spectrum manual, chapter
  24](https://worldofspectrum.net/ZXBasicManual/zxmanchap24.html).
- **Tapes:** [World of Spectrum: TAP
  format](https://worldofspectrum.net/zx-modules/fileformats/tapformat.html)
  and [Kaitai: ZX Spectrum tape
  file](https://formats.kaitai.io/zx_spectrum_tap/).
- **BASIC:** the line format and the five-byte numbers from the [ZX
  Spectrum manual, chapter
  24](https://worldofspectrum.net/ZXBasicManual/zxmanchap24.html); the
  keyword codes from [Wikipedia: ZX Spectrum character
  set](https://en.wikipedia.org/wiki/ZX_Spectrum_character_set).
- **Fuse's menus:** [its manual page](https://manpages.debian.org/wheezy/fuse-emulator-common/fuse.1.en.html).
