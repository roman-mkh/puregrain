-- | Ready-made fixed palettes, for `Puregrain.Palette.nearestColor`.
-- | Each is a plain `NonEmptyArray RGB`, not a `CompiledPalette`, so the
-- | caller picks the distance metric: `compilePalette distance2 cga16`.
-- |
-- | Historical and terminal palettes have no single official RGB
-- | definition — machines were analog, terminals are themable — so each
-- | preset below says where its values come from. Overview, sources and
-- | notes: [docs/palettes.md](https://github.com/roman-mkh/puregrain/blob/master/docs/palettes.md).
-- |
-- | Order matters in one respect: when a pixel is exactly as near to two
-- | colors, `nearestColor` picks the one that comes first.
module Puregrain.Palette.Presets
  ( blackWhite
  , websafe216
  , cga16
  , ansi16
  , ansi256
  , c64
  , zxSpectrum
  ) where

-- Keep docs/palettes.md in step with this module: a new preset means a
-- new row there, and in cli/README.md's short table.

import Prelude

import Data.Array.NonEmpty (NonEmptyArray)
import Data.Array.NonEmpty as NEA
import Data.Int (toNumber)
import Puregrain.Pixel (RGB(..))

rgb :: Int -> Int -> Int -> RGB
rgb r g b = RGB { r: toNumber r, g: toNumber g, b: toNumber b }

-- | Black, then white. With `nearestColor` it dithers a color image
-- | straight down to pure black and white, choosing by RGB distance —
-- | which isn't brightness: pure green is nearer to black.
blackWhite :: NonEmptyArray RGB
blackWhite = NEA.cons' (rgb 0 0 0) [ rgb 255 255 255 ]

-- | The 216 "web-safe" colors: every combination of 0, 51, 102, 153, 204
-- | and 255 per channel (a 6×6×6 cube), `r` varying slowest, so it starts
-- | at black and ends at white. Being a complete grid, its nearest color is
-- | the nearest step in each channel separately — the same result as
-- | `perChannel (nearestLevel (evenRamp 6))`.
websafe216 :: NonEmptyArray RGB
websafe216 = do
  r <- steps
  g <- steps
  b <- steps
  pure (RGB { r, g, b })
  where
  steps = NEA.cons' 0.0 [ 51.0, 102.0, 153.0, 204.0, 255.0 ]

-- | The 16-color IBM PC palette, in index order 0–15: CGA's "RGBI" colors
-- | (each channel 0x00 or 0xAA, plus an intensity bit adding 0x55), with
-- | the IBM 5153 monitor's brown — color 6 is #AA5500, not dark yellow.
-- | The same 16 are EGA's and VGA's defaults (VGA stores 6 bits per
-- | channel, so some tables write A8 for AA) and the DOS text colors; the
-- | Linux console uses the same values, in ANSI order (its vt.c).
-- | Source: en.wikipedia.org/wiki/Color_Graphics_Adapter (RGBI palette).
-- | Wikipedia's terminal-comparison table ("ANSI escape code") has a
-- | "CGA/EGA/VGA" column with display-adjusted numbers (e.g. red 196);
-- | this preset uses the digital values.
-- | (EGA's full 64-color palette is every combination of 0, 85, 170, 255 —
-- | no preset needed: that's `perChannel (nearestLevel (evenRamp 4))`.)
cga16 :: NonEmptyArray RGB
cga16 = NEA.cons' (rgb 0x00 0x00 0x00)
  [ rgb 0x00 0x00 0xAA, rgb 0x00 0xAA 0x00, rgb 0x00 0xAA 0xAA
  , rgb 0xAA 0x00 0x00, rgb 0xAA 0x00 0xAA, rgb 0xAA 0x55 0x00, rgb 0xAA 0xAA 0xAA
  , rgb 0x55 0x55 0x55, rgb 0x55 0x55 0xFF, rgb 0x55 0xFF 0x55, rgb 0x55 0xFF 0xFF
  , rgb 0xFF 0x55 0x55, rgb 0xFF 0x55 0xFF, rgb 0xFF 0xFF 0x55, rgb 0xFF 0xFF 0xFF
  ]

-- | The 16 ANSI terminal colors as xterm's defaults, in index order: black,
-- | red, green, yellow, blue, magenta, cyan, white, then the 8 bright ones.
-- | The ANSI standard names these colors but defines no RGB values, and
-- | every terminal differs; for the Linux console's values use `cga16`
-- | (the same colors, in CGA rather than ANSI order).
-- | Source: xterm's XTerm-col.ad — X11 colors black, red3, green3,
-- | yellow3, blue2, magenta3, cyan3, gray90, gray50, red, green, yellow,
-- | rgb:5c/5c/ff, magenta, cyan, white — matching the xterm column of
-- | en.wikipedia.org/wiki/ANSI_escape_code.
ansi16 :: NonEmptyArray RGB
ansi16 = NEA.cons' (rgb 0 0 0)
  [ rgb 205 0 0, rgb 0 205 0, rgb 205 205 0
  , rgb 0 0 238, rgb 205 0 205, rgb 0 205 205, rgb 229 229 229
  , rgb 127 127 127, rgb 255 0 0, rgb 0 255 0, rgb 255 255 0
  , rgb 92 92 255, rgb 255 0 255, rgb 0 255 255, rgb 255 255 255
  ]

-- | xterm's 256-color palette: `ansi16` (indices 0–15), then a 6×6×6 cube
-- | (16–231; index 16 + 36r + 6g + b, each level 0 or 55 + 40n: 0, 95,
-- | 135, 175, 215, 255), then 24 grays (232–255: 8 + 10i, i.e. 8 … 238).
-- | Source: xterm's 256colres.pl. In a real terminal the first 16 come from
-- | its theme and only the other 240 are fixed. 7 colors appear twice —
-- | the cube repeats ansi16's black, white, and bright red, green, yellow,
-- | magenta and cyan (xterm's bright blue, 92/92/255, isn't in the cube) —
-- | so there are 249 distinct colors; `nearestColor` picks the earlier
-- | index of a pair.
ansi256 :: NonEmptyArray RGB
ansi256 = ansi16 <> cube <> grays
  where
  level n = if n == 0 then 0 else 55 + 40 * n
  cube = do
    r <- NEA.range 0 5
    g <- NEA.range 0 5
    b <- NEA.range 0 5
    pure (rgb (level r) (level g) (level b))
  grays = map (\i -> let v = 8 + 10 * i in rgb v v v) (NEA.range 0 23)

-- | The Commodore 64's 16 colors, in VIC-II index order: black, white, red,
-- | cyan, purple, green, blue, yellow, orange, brown, light red, dark grey,
-- | grey, light green, light blue, light grey. There's no official RGB
-- | definition; these are Pepto's calculated PAL values (2001, gamma
-- | corrected), the de facto reference.
-- | Source: pepto.de/projects/colorvic/2001/
c64 :: NonEmptyArray RGB
c64 = NEA.cons' (rgb 0x00 0x00 0x00)
  [ rgb 0xFF 0xFF 0xFF, rgb 0x68 0x37 0x2B, rgb 0x70 0xA4 0xB2
  , rgb 0x6F 0x3D 0x86, rgb 0x58 0x8D 0x43, rgb 0x35 0x28 0x79, rgb 0xB8 0xC7 0x6F
  , rgb 0x6F 0x4F 0x25, rgb 0x43 0x39 0x00, rgb 0x9A 0x67 0x59, rgb 0x44 0x44 0x44
  , rgb 0x6C 0x6C 0x6C, rgb 0x9A 0xD2 0x84, rgb 0x6C 0x5E 0xB5, rgb 0x95 0x95 0x95
  ]

-- | The ZX Spectrum's 15 distinct colors: its 8 colors (black, blue, red,
-- | magenta, green, cyan, yellow, white) at normal brightness, then the 7
-- | non-black ones with BRIGHT set (bright black is just black). The real
-- | colors were never measured; this uses the common model of normal = 85%
-- | of bright, 0xD8 = 216 ≈ 0.85 × 255 (en.wikipedia.org/wiki/
-- | ZX_Spectrum_graphic_modes; values as lospec.com/palette-list/zx-spectrum).
-- | Many emulators use 0xD7 or 0xCD instead.
-- | This is the per-pixel palette only: the real machine allowed just 2 of
-- | these colors per 8×8 cell, which this library doesn't model (yet).
zxSpectrum :: NonEmptyArray RGB
zxSpectrum = normal <> bright
  where
  -- The 7 non-black colors as on/off channels, in ZX color-code order 1-7.
  hues = NEA.cons' { r: 0, g: 0, b: 1 }
    [ { r: 1, g: 0, b: 0 }, { r: 1, g: 0, b: 1 }, { r: 0, g: 1, b: 0 }
    , { r: 0, g: 1, b: 1 }, { r: 1, g: 1, b: 0 }, { r: 1, g: 1, b: 1 }
    ]
  at v c = rgb (c.r * v) (c.g * v) (c.b * v)
  normal = NEA.cons' (rgb 0 0 0) (NEA.toArray (map (at 0xD8) hues))
  bright = map (at 0xFF) hues
