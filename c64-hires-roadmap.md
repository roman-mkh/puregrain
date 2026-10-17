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
| Bitmap | 8000 bytes |

The 16 colors are the library's `c64` preset (Pepto's values), in the
VIC-II's index order: black, white, red, cyan, purple, green, blue, yellow,
orange, brown, light red, dark grey, grey, light green, light blue, light
grey. Dark grey, grey and light grey have r = g = b, so they lie on the
line from black to white.

Sources: [C64-Wiki: Standard Bitmap
Mode](https://www.c64-wiki.com/wiki/Standard_Bitmap_Mode),
[Pepto's palette](https://www.pepto.de/projects/colorvic/2001/).

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
8. **Outputs:** a PNG; a self-displaying `.prg` first; then a standard
   hires picture format.
9. **The `.prg` viewer is BASIC, not 6502 code:** a few lines that switch
   the video chip to bitmap mode, copy the 1000 color bytes into place and
   wait for a key, followed by the picture in the same file. It's the C64
   counterpart of the Spectrum tape's loader, `10 LOAD "" SCREEN$: PAUSE 0`.
   A C64 picture file is only data: loading it shows nothing until the
   video chip is switched over, so an emulator alone can't show one.

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

## Open questions

Answers go here as they're decided.

- **The viewer's details:** the border's color (black, or the picture's
  most frequent color?); after a key, back to text mode, or stay?
- **The library's names** for the hires mode and the writers, chosen with
  room for multicolor: for example `hiresScreen`, `toHiresPrg`,
  `toHires<Format>`. To decide in phases 1 and 3.
- **The standard format:** which one, after the research in phase 0.

## Progress

- [ ] 0. Verify and design
- [ ] 1. Library
- [ ] 2. CLI
- [ ] 3. The `.prg`
- [ ] 4. The standard hires picture format
- [ ] 5. The recommended mode and delivery
