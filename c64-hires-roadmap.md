# C64 hires: roadmap

The working document of the branch `c64-hires`: goal, decisions, open
questions, phases, progress. Before the pull request, its content moves to
its permanent homes, and this file is deleted:

- user docs to `docs/machine-screens/c64.md` and `cli/README.md`;
- decisions and their reasons to `CLAUDE.md`;
- changes to `CHANGELOG.md`, under Unreleased;
- anything still open to `TODO.md`.

## Goal

Dither pictures to the Commodore 64's hires bitmap screen, in the library
and on the command line (`--machine c64-hires`). The results come as a PNG,
as a self-displaying `.prg` that an emulator starts directly, and as a
standard hires picture file for paint programs.

The C64's multicolor bitmap mode is a separate, later task
(`c64-multicolor`). It needs changes to the cells API that hires doesn't:
up to 4 colors per cell, a background shared by the whole screen, and
double-wide pixels.

## The machine

Verified so far:

| | Hires bitmap mode |
|---|---|
| Pixels | 320×200 |
| Cells | 8×8, 40 across and 25 down |
| Colors per cell | 2 of 16, any two |
| Where they come from | screen RAM, one byte per cell: the upper nibble is the color of the 1 bits, the lower nibble the color of the 0 bits; color RAM isn't used |
| Bitmap | 8000 bytes, cell by cell: each cell's 8 bytes in a row, the top pixel row first; the cells left to right, then top to bottom. A byte's highest bit is the leftmost pixel |

The 16 colors are the library's `c64` preset (Colodore's values since
2026-10-17, see "Notes from the work"), in the
VIC-II's index order: black, white, red, cyan, purple, green, blue, yellow,
orange, brown, light red, dark grey, grey, light green, light blue, light
grey. Dark grey, grey and light grey have r = g = b, so they lie on the
line from black to white.

So the byte for the pixel at (x, y) is (y / 8) × 320 + (x / 8) × 8 +
(y mod 8), with integer division, and its bit is 7 − (x mod 8). The
sources describe the layout in words; the formula is derived from it.

Sources: [C64-Wiki: Standard Bitmap
Mode](https://www.c64-wiki.com/wiki/Standard_Bitmap_Mode),
[Compute!: Bitmap Graphics On The
64](https://www.atarimagazines.com/compute/issue43/208_1_Bitmap_Graphics_On_The_64.php),
[Colodore](https://www.pepto.de/projects/colorvic/), with VICE's
settings ([colodore.vpl](https://raw.githubusercontent.com/VICE-Team/svn-mirror/main/vice/data/C64/colodore.vpl)).

## Decisions

1. **Two machine names:** `c64-hires` now, `c64-multicolor` later. A mode
   with its own cell size and color rules is effectively another screen,
   and it adds no new `--machine-*` option.
2. **One library module,** `Puregrain.Machine.C64`, for both modes, by the
   rule of one module per machine. Hires adds its mode now; names leave
   room for multicolor (no type called just `Cell`).
3. **Colors:** the 16 colors as indices 0 to 15, with their C64 names, and
   their values from the `c64` preset.
4. **Which color is which in a pair,** as on the ZX Spectrum: the darker
   color is the foreground, the 1 bits, like the Spectrum's ink; the
   lighter is the background, the 0 bits. A single-color cell has only 0
   bits. With ordered dithering, the darker color is the pattern's base.
   Darker means a lower luma, 0.299 R + 0.587 G + 0.114 B of the preset's
   values, since the C64's codes, unlike the Spectrum's, aren't in order
   of brightness. Seven pairs have almost equal luma by the C64's design
   (green 116.7 and light red 116.6, for example); there the tiny
   difference decides, deterministically, and on exact equality the lower
   code. It sets only the direction of an ordered pattern, not its tone.
5. **Candidates and their order,** as on the ZX Spectrum: 16 single colors
   and 120 pairs, 136 in all; single colors first, then pairs by the
   distance between their colors, nearest first; equal distances by index.
   The order matters here too: a cell of black and grey also fits black
   and white perfectly, since grey lies on their line, and only the nearer
   pair, listed first, keeps such a cell unchanged.
6. **`--machine-palette`:** `c64-hires` offers only `full`. `normal` and
   `bright`, the Spectrum's terms, are rejected with the machine's list.
7. **Sizes:** the machine's files need exactly 320×200; a PNG can have any
   size, with a note, as on the Spectrum.
8. **Outputs:** a PNG; a self-displaying `.prg` first; then an Art Studio
   file, `.art`, the standard hires picture format (see "Phase 0 results").
9. **The `.prg` viewer is BASIC, not 6502 code:** a few lines that switch
   the video chip to bitmap mode, copy the 1000 color bytes into place and
   wait for a key, followed by the picture in the same file. It's the C64
   counterpart of the Spectrum tape's loader, `10 LOAD "" SCREEN$: PAUSE 0`.
   A C64 picture file is only data: loading it shows nothing until the
   video chip is switched over, so an emulator alone can't show one.
10. **The viewer's border is black** (decided 2026-10-17): simple, the
    usual frame, and a black screen while the colors are copied looks like
    loading. Matching the picture's edge is a later idea (below).
11. **Names** (decided 2026-10-17): in the library `hiresScreen`,
    `HiresCell` with `foreground` and `background` as color codes,
    `hiresCells`, `hiresPalette`; later `toHiresPrg` and `toArtStudio`. On
    the command line, the format names `prg` and `art`, both only with
    `--machine c64-hires`.

## Phases

0. **Verify and design, no code.** Check each fact the code will rely on
   against a source, and record it here:
   - the bitmap's byte order: 8 consecutive bytes per cell, the cells row
     by row; which bit is the leftmost pixel;
   - the `.prg` file: its two-byte load address, and C64 BASIC V2's
     program format (each line: the address of the next line, the line
     number, the tokens, a 0; the program ends with two 0s), with the
     token codes the viewer needs;
   - the video chip's registers for bitmap mode: the mode bit in 53265
     ($D011), the memory pointers in 53272 ($D018) for the screen RAM and
     the bitmap, the border color in 53280 ($D020);
   - the memory layout the `.prg` loads into, so the bitmap starts where
     the video chip can show it;
   - how emulators start a `.prg` (VICE, and an online emulator to check
     with, as JSSpeccy was for the tape);
   - the standard hires picture formats that tools open most widely, and
     the layout of the one we choose.
1. **Library:** `Puregrain.Machine.C64` with the colors, the hires
   candidates in their order, and the hires `CellMode`. Tests as for the
   Spectrum: count, order, colors against values written independently,
   and valid pictures unchanged with any kernel and rule.
2. **CLI:** `--machine c64-hires`, the per-machine `--machine-palette`
   check, the size note, PNG output; tests; an end-to-end exact check with
   a test image of valid hires cells, like `color:zx-cells`.
3. **The `.prg`:** the writer in the library, an independent reader in the
   tests, `.prg` as an output format of the CLI, an end-to-end check; then
   a check by you in an emulator.
4. **The standard hires picture format:** the writer, an independent
   reader, an end-to-end check.
5. **The recommended mode and delivery:** a visual comparison (Bayer 8,
   Atkinson, the others) to choose the sample's mode; `npm run
   dither:c64`; the docs (`docs/machine-screens/c64.md`, the machine table,
   the CLI README); CHANGELOG, CLAUDE.md, TODO.md; this file deleted; the
   pull request.

## Phase 0 results

### The `.prg`: a BASIC viewer and the picture, in one file

A `.prg` file is its load address, two bytes, low byte first, followed by
the bytes to load there. Ours loads at 2049 ($0801), where BASIC programs
start, so the C64's own `LOAD` and `RUN`, or an emulator's autostart, run
it.

| Address | Content |
|---|---|
| $0801 | the BASIC viewer, then two zero bytes, the end of the program |
| up to $1FFF | zeros |
| $2000–$3F3F | the bitmap, 8000 bytes |
| $3F40–$4327 | the screen RAM, 1000 bytes: the cells' colors |

That's 15,145 bytes. The bitmap sits where the video chip can show it,
and the colors follow it, as in an Art Studio file. The viewer copies the
colors to the screen RAM at 1024 ($0400); BASIC keeps its variables after
the end of the loaded file, so nothing overlaps.

The viewer, about six lines (the exact text is settled in phase 3):

```
10 B=PEEK(53280):D=PEEK(53265):M=PEEK(53272)
20 POKE 53280,0:POKE 53265,D AND 239
30 FOR I=0 TO 999:POKE 1024+I,PEEK(16192+I):NEXT
40 POKE 53272,24:POKE 53265,D OR 32
50 GET K$:IF K$="" THEN 50
60 POKE 53265,D:POKE 53272,M:POKE 53280,B:PRINT CHR$(147)
```

1. Remember the border color and the two video registers, so they can be
   put back as they were, whatever mode the machine was in.
2. Black border, screen blanked: clearing bit 4 of 53265 ($D011) shows
   only the border color, so the copying isn't seen.
3. Copy the 1000 colors from 16192 ($3F40) to the screen RAM at 1024; a
   few seconds in BASIC.
4. Bitmap at 8192 ($2000) and screen RAM at 1024: 53272 ($D018) = 24.
   Bitmap mode on, screen shown again: bit 5 of 53265 set.
5. Wait for a key.
6. Put everything back and clear the text screen.

How a C64 BASIC line is stored: the address of the next line (two bytes,
low first), the line number (two bytes, low first), the text with each
keyword one byte, and a zero; the program ends with two zero bytes. Unlike
the Spectrum, numbers in the text are plain digits. The token codes the
viewer needs: `FOR` $81, `NEXT` $82, `IF` $8B, `POKE` $97,
`PRINT` $99, `GET` $A1, `TO` $A4, `THEN` $A7, `+` $AA, `AND` $AF, `OR`
$B0, `=` $B2, `PEEK` $C2, `CHR$` $C7.

Sources: [C64-Wiki: BASIC token](https://www.c64-wiki.com/wiki/token)
(the line format, with a worked example, and the token codes);
[C64-Wiki: 53272](https://c64-wiki.com/wiki/53272) (the screen RAM in
bits 4 to 7, × 1024; the bitmap at 8192 with bit 3);
[C64-Wiki: 53265](https://c64-wiki.com/wiki/53265) and [a commodore.ca
thread](https://commodore.ca/forum/viewtopic.php?p=17011) (bit 4 blanks
the screen, 27 is the usual value); [A C64 Game, step
25](https://gamedev.net/blog/949/entry-2250713-a-c64-game-step-25/) (bit 5
is bitmap mode).

### The standard format: Art Studio, `.art`

Art Studio was the C64's best-known hires paint program, and its format is
the one tools open most widely: RECOIL, the library behind many image
viewers, reads it, and converters write it. Its layout:

| Bytes | Content |
|---|---|
| 0–1 | the load address, $2000 |
| 2–8001 | the bitmap |
| 8002–9001 | the screen RAM: the upper nibble for 1 bits, the lower for 0 bits |
| 9002–9008 | seven zero bytes of filler |

9009 bytes in all; readers accept 9002 to 9009. The alternative, Doodle
(screen RAM first, at $5C00, then the bitmap at $6000), is equally simple
but less widespread.

Sources: [docs.rs: format198x Art
Studio](https://docs.rs/format198x-commodore-c64-art-studio/latest/format198x_commodore_c64_art_studio/)
(the layout, and that readers accept 9002 to 9009 bytes);
[RECOIL's format list](https://recoil.sourceforge.net/formats.html) (Art
Studio and Doodle among the C64 hires formats); [C64-Wiki:
Doodle](https://www.c64-wiki.com/wiki/Doodle). The Archive Team's file
format wiki, "Just Solve the File Format Problem", agrees (files start
with 00 20, usually 9002, 9003 or 9009 bytes), but only reached us through
a search summary; the page didn't load. The docs.rs crate calls its layout
community knowledge, not checked against a reference, so phase 4 confirms
it: our file must open correctly in a RECOIL viewer.

### How to check the files without a C64

- **The `.prg`:** VICE starts a `.prg` dropped onto its window. In the
  browser, [c64-emu](https://github.com/nippur72/c64-emu),
  [ty64](https://ty64.krissz.hu/documentation/en/) and VICIOUS load a
  dropped `.prg`, as JSSpeccy did for the tape.
- **The `.art`:** RECOIL's viewers, as standalone apps or image viewer
  plugins for Windows, macOS, Linux and Android, and in the browser
  ([recoil.sourceforge.net](https://recoil.sourceforge.net/)).

Sources: [VICE 6 manual](https://vice-emu.sourceforge.io/vice_6.html),
[an itch.io report](https://itch.io/post/14409861) (dropping a `.prg`
starts it).

## Open questions

None at the moment; the three from phase 0 are decided (decisions 10 and
11).

## Later ideas

These go to TODO.md when this file is dissolved.

- **The viewer's border in the color along the picture's edge,** so that a
  picture with light edges blends into the border instead of being framed
  in black. Cheap: count the 16 colors over the 1,436 edge pixels.
- **Multicolor** (`c64-multicolor`): `multicolorScreen`, `toMulticolorPrg`,
  `toKoala`, with the cells API questions noted under "Goal".

## Notes from the work

- **Test discovery** accepted only letters in a spec's name
  (`[A-Za-z]+`), so `C64Spec` would silently never have run; it now
  accepts digits too (phase 1).
- **Single colors first** is about the cell's choice, not the picture: a
  one-color cell always has a pair that contains its color as an endpoint
  and is narrower than any pair that only passes through it, so its pixels
  stay exact either way. So the "pictures unchanged" property can't guard
  this order; the ordering test does (mutation-checked, phase 1).
- **`DitheredScreen`** (phase 2): the CLI's `ditherScreen` returns one
  constructor per machine, `ZxDithered` or `C64HiresDithered`, since each
  holds its own machine's cells, which its files need; `screenImage`
  reads the picture for a PNG. Phase 3 adds `prg` the same way: a
  `FormatName`, its rows in `formatChoice` (only with `c64-hires`, no
  wildcard), the size error in `screenSizeCheck`, and a function like
  `screenFile` that gives the bytes for `C64HiresDithered` and `Left` for
  a ZX screen.
- **The palette** (2026-10-17): with Pepto's 2001 values, the `c64`
  preset's until then, a test photo came out almost gray; even the best
  possible mixes of those colors keep only 42% of its color. `c64`
  switched to Colodore at VICE's settings (77% at best), as its own
  commit; the hires order and foregrounds follow by themselves, since
  they're computed from the preset. Details: CLAUDE.md, palettes.md.
- **The `color:c64-cells` tile** shares the drawing with `color:zx-cells`
  (the ZX tile stayed byte-identical). 136 is a multiple of the 4
  patterns, so each hires cell always gets the same pattern (the ZX's 71
  cycle through all four); the exact check depends only on which colors a
  cell holds, so that's fine.

## Progress

- [x] 0. Verify and design
- [x] 1. Library: `Puregrain.Machine.C64` with `hiresScreen`; `C64Spec`
- [x] 2. CLI: `--machine c64-hires`, PNG output; tests; the `color:c64-cells` check
- [ ] 3. The `.prg`
- [ ] 4. The standard hires picture format
- [ ] 5. The recommended mode and delivery
