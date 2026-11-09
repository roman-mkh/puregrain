# Spec: dithering in linear light

A working document (begun 2026-11-06, on the branch `linear-light`), the
specification for dithering in linear light in the library, the CLI and
the web UI. It's written so that anyone can implement it from here. After
the merge it's deleted: what lasts moves to the reference docs,
`CLAUDE.md` or `TODO.md`.

Read first: `CLAUDE.md` (the project's decisions and conventions) and
`CONTRIBUTING.md` (branches, checks, versions, releases).

**Status:** the architecture is settled. The [open
decisions](#open-decisions) come next, one at a time. No code yet, and
nothing here has been prototyped except the measurements it quotes.

## The problem

The eye averages light, but dithering keeps the average of the stored
values, and stored sRGB values aren't proportional to light. Gray 128 has
only 21.6% of white's light, yet it gets about 50% white dots.

With 2 levels, a stored gray looks much lighter at 100% on an sRGB
screen: 32 looks like 99, 64 like 137, 128 like 188, 192 like 225. With
more levels the effect shrinks: 128 looks like 137 with 4 levels, and
like 131 with 6.

## Decided

- **On by default, with an option to turn it off** (the user, 2026-10-21).
- **When:** after the web UI's v2, before v3 (2026-10-21). The web UI gets
  the switch too.
- **Every picture counts as sRGB** (2026-11-06). Neither client reads
  color profiles: both dither the stored numbers, the web UI on purpose,
  so that its results match the CLI's. A Display P3 picture has the same
  curve, so its light comes out right, and its colors are as slightly off
  as they are today. Adobe RGB (a curve of about 2.2) and Apple RGB (1.8)
  come out a little off in brightness too. The docs state it as a limit;
  converting profiles would be a separate feature.
- **CIELAB and OKLab come later, on top** (2026-11-06). Linear light says
  how much light there is, and the error stays in it; these two say which
  color looks nearest, so they only matter where a nearest color is
  chosen. Both start from linear light, and they'd plug into
  `compilePalette`, which takes its distance as a function.

## The architecture (settled 2026-11-06)

A wrapper around the whole dithering, not around the quantizer:

```
today:   stored ───────────────► dither ───────────────► stored

linear:  stored ─► to linear ─► dither ─► to stored ─► stored
                                (same code)
```

Three rules:

1. **The error stays in linear light,** and is never converted.
2. **The targets are converted once, before the first pixel:** the driver
   passes the conversion to the quantizer ([decision
   1](#decision-1-the-librarys-api)), and the constructors' formulas then
   run on linear numbers unchanged.
3. **Each row is converted once on the way in and once on the way out,**
   so `ditherImage`, `ditherRows` and the stepper all keep working.

What each quantizer does with its values, once the driver has passed the
conversion:

```
threshold t               becomes  threshold (toLinear t)
nearestLevel levels       becomes  the nearest by stored values, output in linear light (decision 3)
ordered bayerMap levels   becomes  ordered bayerMap (map toLinear levels)
nearestColor palette      becomes  the nearest by stored values, output in linear light (decision 3)
```

What the driver does, for black and white; the caller only writes
`ditherImage floydSteinberg (threshold 128.0) image`:

```purescript
dithered image =
  map (map toStored)                  -- 3. each row back to stored values
    (ditherImage floydSteinberg
      (threshold (toLinear 128.0))    -- 2. the target, once
      (map (map toLinear) image))     -- 3. each row to linear
```

### Why not something simpler

Measured on a flat gray 128 (2026-11-06):

| Floyd–Steinberg, to black and white | White dots | Looks like gray |
|---|---:|---:|
| Today | 50.2% | 188 |
| A wrapper around `quantize`, the error in stored values | 50.0% | 188 |
| The error in linear light | 21.5% | 128 |

| Pure Bayer 8, to black and white | White dots |
|---|---:|
| Decided on stored values | 50.0% |
| Decided on linear values | 21.9% |

- **The error can't stay in stored values.** Error diffusion keeps the
  average of the numbers the error is in, so a wrapper around `quantize`
  changes where dots land, not how many there are.
- **An error can't be converted on its own.** Stored 20 to 30 adds 0.006
  of light, stored 200 to 210 adds 0.067: the same error means 11 times
  more light, depending on the pixel.
- **`Quantize` can't be a Functor:** it's `Context -> a -> a`, so `a` goes
  both in and out. `Invariant`'s `imap` fits the type and would wrap any
  quantizer, but it leaves the decision on stored values, which is wrong
  for pure Bayer (the table above: no error is passed on to correct it),
  and it needs the back formula on every pixel.

### The conversion

The sRGB standard's formula, the same for red, green and blue, with no
mixing of channels:

```
to linear (c = stored / 255):
  if c ≤ 0.04045:  c / 12.92
  otherwise:       ((c + 0.055) / 1.055) ^ 2.4

back (L = linear, then × 255):
  if L ≤ 0.0031308:  12.92 × L
  otherwise:         1.055 × L ^ (1 / 2.4) − 0.055
```

**Linear values keep the 0–255 scale,** because `threshold` always
outputs 0 or 255. Gray 128 becomes about 55, the 4 levels 0, 85, 170, 255
about 0, 23, 103, 255, and stored (128, 64, 200) about (55, 13, 147).

The channels' different weight for the eye (in linear light, gray is
0.2126 R + 0.7152 G + 0.0722 B) doesn't belong here: `toLinear` says how
much light each channel gives, not how much the eye values it.

### What follows from it

- **A threshold without diffusion gives the same picture as today:** the
  curve keeps the order of the values, so what's below 128 stays below
  the converted 128.
- **Levels and palettes without diffusion give today's picture too:** the
  nearest level or color is chosen on stored values ([decision
  3](#decision-3-the-nearest-color-or-level)).
- **A custom quantizer** (`quantize f`): see [decision
  1](#custom-quantizers-and-runquantize).
- **`RGBA` needs its own handling:** its `mapChannels` includes alpha,
  which isn't on the sRGB curve. Neither client dithers `RGBA` today.
- **Machine cells need their colors converted too.** `CellPalette` is
  opaque, so `Puregrain.Cells` or the machine modules need a way to do
  that. The line between a cell's two colors is a true mix of light in
  linear values.
- **`channelToStored` must round to whole numbers:** `Zx.toScr` and the
  C64's writers compare each pixel with its cell's colors exactly, and
  rounding brings all 256 bytes back exactly (tested 2026-11-06).

## Decision 1: the library's API

Settled 2026-11-08. The conversion is the driver's choice, not the
quantizer's: it describes the picture, how its numbers relate to light.

- **One value holds both directions,** so they can't be mismatched. Two
  presets: `srgb`, the default, and `asStored`, today's behaviour (the
  identity both ways). Other curves, such as Adobe RGB's (a power of
  about 2.2) or Apple RGB's (1.8), come through a checked constructor, as
  `fromOffsets` checks kernels: the two functions must be each other's
  inverse, rise steadily, and keep 0 as 0 and 255 as 255 (`threshold`
  outputs exactly those, and the machines' files need their colors back
  exactly).
- **The drivers default to `srgb`** and keep their names and arguments:
  from 0.3.0 on, `ditherImage`, `ditherRows`, `initDithering`,
  `ditherCells` and `ditherBands` give other pictures from the same
  code. Each has a twin that takes the conversion first:
  `ditherImageWith`, `ditherRowsWith`, `initDitheringWith`,
  `ditherCellsWith` and `ditherBandsWith`. `ditherRow` needs none, since
  the stepper's state holds the conversion. The internal
  `ditherImageWith` and `ditherRowsWith` of `Puregrain.Internal.Image`
  get other names.
- **`Quantize` takes the conversion from the driver.** It's opaque, so its
  inside can change, and callers still write `threshold 128.0`. The
  driver passes the conversion once, before the first pixel, and keeps
  the resulting function: passed per pixel, the targets would be
  converted again for every pixel, since PureScript shares nothing by
  itself. The cells' quantizer and palettes work the same way.
- **The drivers need one more constraint,** to convert channel by channel
  (`MapChannels`, or a class of its own): `RGBA`'s alpha isn't on any
  light curve, so it must not be converted.
- **Release 0.3.0,** and the CHANGELOG says it loudly: the same code gives
  other pictures, and `…With asStored` gives the old ones.
- **Pinned by tests:** `…With asStored` equals the test reference, as
  `ditherImage` does today. Before the merge, the CLI's opt-out must give
  today's files byte for byte for a set of configurations, as the reshape
  of 2026-10-04 was checked.

```purescript
-- both directions, per channel, on the 0–255 scale (opaque)
data Encoding
srgb     :: Encoding
asStored :: Encoding
encoding :: (Number -> Number) -> (Number -> Number) -> Either String Encoding

-- applying it to a pixel, a level or a color, channel by channel
toLinear :: forall a. MapChannels a => Encoding -> a -> a
toStored :: forall a. MapChannels a => Encoding -> a -> a

ditherImage
  :: forall a. Ring a => Scalable a => MapChannels a
  => Kernel -> Quantize a -> Array (Array a) -> Array (Array a)
ditherImage = ditherImageWith srgb

ditherImageWith
  :: forall a. Ring a => Scalable a => MapChannels a
  => Encoding -> Kernel -> Quantize a -> Array (Array a) -> Array (Array a)
```

`Encoding`, `srgb`, `asStored`, `encoding`, `toLinear` and `toStored` are
placeholders, to be named in decision 7.

### Custom quantizers and `runQuantize`

`Quantize` gets the conversion from the driver, once, before the first
pixel:

```purescript
-- inside the library; opaque, as today
newtype Quantize a = Quantize (Encoding -> Context -> a -> a)
```

The driver gets the per-pixel function the same way for every
quantizer, once per run, through an internal function (`quantizerFor`,
the name agreed with the user):

```purescript
quantizerFor :: forall a. Encoding -> Quantize a -> Context -> a -> a
quantizerFor enc (Quantize q) = q enc
```

What that function still does for each pixel, besides deciding, depends
on how the quantizer was built:

| Built with | Extra work per pixel |
|---|---|
| `quantizeLinear`, coefficients converted in the outer `let` | none |
| `quantizeLinear`, converted inside the per-pixel function | the coefficients, every pixel |
| `quantize f` or `quantizeWith f` | the pixel, both ways |

The rows' own conversion, in and out, is the driver's, the same for all.

**The main way: a new constructor that hands the author the conversion**
(`quantizeLinear` here; its name is open). The author converts their
coefficients once, in the outer function, and returns the function the
driver runs for every pixel, which decides on linear values. **Only one
direction is needed:** `toLinear`, for the coefficients. The way back to
stored values is the driver's, for the whole row, and values that are
the same on both scales, such as 0 and 255, need no conversion at all.
The presets are built this way themselves, which shows the constructor
is enough:

```purescript
quantizeLinear :: forall a. (Encoding -> Context -> a -> a) -> Quantize a
quantizeLinear = Quantize

threshold t = quantizeLinear \enc ->
  let t' = toLinear enc t                 -- 128 becomes 55, once
  in \_ x -> if x < t' then 0.0 else 255.0

nearestLevel levels = quantizeLinear \enc ->
  let ls = map (toLinear enc) levels      -- 85 and 170 become 23 and 103, once
  in \_ x -> nearestOf ls x
```

A custom quantizer with coefficients does the same. For example, three
tones, black, mid gray and white:

```purescript
threeTones = quantizeLinear \enc ->
  let lo   = toLinear enc 64.0
      hi   = toLinear enc 192.0
      gray = toLinear enc 128.0           -- an output that isn't 0 or 255
  in \_ x -> if x < lo then 0.0 else if x < hi then gray else 255.0
```

The `let` must stay outside the inner function: inside it, the
coefficients would be converted again for every pixel, since PureScript
shares nothing by itself. With `asStored`, every quantizer built this
way behaves exactly as today.

**The last resort: `quantize f` and `quantizeWith f`,** for an `f` whose
coefficients the library can't see. `f` keeps its meaning, stored values
in and out, as the docs say today: the library converts each pixel back
to stored before `f`, and `f`'s result to linear after it. That's `imap`
from `Invariant`, a line inside the library, with no new dependency and
nothing for the author to implement. The error still stays in linear
light, so with any kernel the tones come out right, and without
diffusion `f` decides as today. The price: both directions for every
pixel, so it's slower, and decision 2's exactness question applies. Both
constructors gain the constraint the drivers gain, for the conversion:

```purescript
quantize :: forall a. MapChannels a => (a -> a) -> Quantize a
quantize f = Quantize \enc _ x -> toLinear enc (f (toStored enc x))
```

**`runQuantize` answers for a stored value:** it converts in and out,
with `srgb` by default, and `runQuantizeWith` takes the conversion. With
`asStored`, it's today's `runQuantize`. Both are built on
`quantizerFor`:

```purescript
runQuantizeWith :: forall a. MapChannels a => Encoding -> Quantize a -> Context -> a -> a
runQuantizeWith enc q ctx v = toStored enc (quantizerFor enc q ctx (toLinear enc v))

runQuantize = runQuantizeWith srgb
```

## Decision 2: exactness across browsers

Settled 2026-11-09. "The same results everywhere" is the feature the
project can't trade off (the user, 2026-11-08), and `Math.pow` doesn't
keep it: in the prototype, Node 22, which the CLI and CI run on, and the
browsers disagree on a tenth of the conversions.

- **Our own two functions, in PureScript, from exact operations only**
  (`+`, `−`, `×`, `÷` and `√`). To linear, x^2.4 = x² × (x^(1/5))², the
  fifth root from 8 Newton steps starting at 1. Back, L^(5/12) = √√L ×
  √(∛L), the cube root from 7 Newton steps starting at the fourth root.
  The number of steps is fixed, so every engine ends on the same value,
  even where Newton bounces between two neighbouring numbers. PureScript
  rather than a foreign function (the user, 2026-11-09): the library
  stays free of JavaScript and works with other backends, and the
  self-check below would show a compiler that changed the arithmetic.
- **The table of 256 values is computed from those functions, once,**
  when first needed or when the module loads: no numbers written into
  the source, and the table always agrees with the functions. Values
  that aren't whole numbers go through the functions: once per run in a
  quantizer's outer `let`, and per pixel only for a library user's
  fractional pixels and the last resort. The way back finds a target
  that came from the table in it exactly, in about 8 comparisons, and
  converts others through the function.
- **The step counts are verified up to stored 300;** below about 10, the
  curve's straight part needs no steps. The implementation clamps to the
  verified range, or verifies a wider one.
- **A self-check** shows on every engine whether this holds (below).

### The prototype (2026-11-08)

Scratch scripts in JavaScript, which PureScript compiles to: the two
functions, the same with `Math.pow` for comparison, and a fingerprint, a
digest of 200,399 values each converted three ways (to linear, back, and
the round trip), run in Node on the host and, in Playwright's Docker
image, in Node and three browsers.

| Environment | Ours | `Math.pow` |
|---|---|---|
| Node 22.14 (host) | `27cc74ff` | `4199f386` |
| Node 26.13 | `27cc74ff` | `55c02ab6` |
| Chromium 156 | `27cc74ff` | `55c02ab6` |
| Firefox 157 | `27cc74ff` | `55c02ab6` |
| WebKit 27.2 | `27cc74ff` | `55c02ab6` |

- **`Math.pow` in Node 22 differs from the rest** on 19,204 of the
  200,399 conversions to linear and 19,461 back. Byte 18 is one: Node 22
  gives 1.542452420828549, the others 1.5424524208285488; ours gives
  1.5424524208285484 everywhere.
- **Accuracy, against the exact values** (computed with `BigInt`, bytes 1
  to 255): ours at most 5.9 steps off, and the nearest possible number
  for 48 of them; `Math.pow` at most 7.8 steps off, and the nearest for
  40. Both are a few steps off because c, 0.055 and 1.055 are rounded
  before the power: differences around the 16th significant digit.
- **Steps:** the fifth root needs at most 8 from 1, the cube root at most
  7 from the fourth root (11 from 1). About 6% of the values end
  bouncing between two neighbouring numbers, at most 2 steps apart.
- **Round trip and order:** every byte comes back exactly after rounding
  (before rounding, within 6 × 10⁻¹⁴). The table rises strictly, and so
  do the halves between bytes. Over a million sorted values, no larger
  input gave a smaller result, in either direction.
- **Speed** (Node 22, rough): the whole table 7 µs; a lookup 0.9 ns; our
  formula 37 ns, `Math.pow` 48 ns; back, a target found in the table
  11 ns, the formula 36 ns. Dithering costs about 1,900 ns per pixel.

### The self-check

A function of the library runs the fingerprint on the engine it runs
on, and reports whether the results are the reference's:

```purescript
checkPlatform   :: Effect PlatformReport          -- about 20 ms in Node
exactArithmetic :: PlatformReport -> Boolean      -- one accessor per check
problems        :: PlatformReport -> Array String -- one sentence per failed check
```

The report also holds the first value whose results differed, for
diagnosis. The names are placeholders, for decision 7.

- **The fingerprint's inputs are fixed:** the 256 bytes, the fractional
  levels of 2 to 16 levels, special values (thresholds such as 96.5, the
  curve's switch points, values just outside 0–255), and 200,000 values
  from Park and Miller's "minimal standard" generator with a fixed seed:
  next = 48271 × x mod (2^31 − 1), computed in `Number`, exact since
  48271 × x stays below 2^53. Each is converted both ways and in the
  round trip, and folded into a digest.
- **Our own three lines for the generator,** although the `lcg` package,
  which QuickCheck uses, is the same generator: as a library dependency,
  every user would inherit it, and a future version could change the
  inputs. A plain loop that calls itself, with no array of values and no
  `State`.
- **The digest comes from the values' exact parts,** split with exact
  operations (multiplying and dividing by powers of 2 is exact), not from
  their printed digits: the standard leaves the last printed digit open,
  so two engines could print the same number differently.
- **200,000 values,** so that the engines' optimizing compilers run too:
  the classic risk, fusing a multiply and an add into one step, which the
  standard forbids, would only show in that "hot" code. About 20 ms.
- **`Effect`, not a pure value:** the check observes the engine at a
  moment, and on a faulty engine two runs could differ. A compiler may
  compute a pure value once and reuse it, or move it, as
  `purs-backend-es` moved the CLI's timing (2026-10-10). It also leaves
  room for future checks with effects.
- **Typed, and open to more checks:** an opaque report with one accessor
  per check, and `problems`, so that a client can print warnings without
  knowing every check.
- **Nothing runs on import.** Users who need the same results call it, and
  the clients call it themselves:
  - **CLI:** a mode of its own, like `--help`, without INPUT or OUTPUT. It
    says so when everything passes, and exits with 1 when a check fails.
    Not before every dithering: the platform doesn't change between runs.
  - **Web UI:** one more instance of `worker.js`, started once from the
    copy kept in memory, with a new message, "check", so dithering never
    interrupts it. The page shows a notice if there are problems; its
    design comes later.
  - **CI:** the check in Node, and in the three browsers through
    `check:web`.
- **One stored constant:** the fingerprint's digest, in the library's
  source. It changes only when the conversion changes on purpose, in the
  same commit and with a CHANGELOG line, since every picture then changes
  slightly; never just to make CI pass.
- **On a mismatch, the build fails.** Then, depending on the cause, our
  code is fixed; an engine's bug is reported, worked around where
  possible, and its version named in the docs; or a compiler's change is
  met by adjusting the code, or by moving that part into a foreign
  function.
- **Honest wording:** a passing check means "this engine computed the
  reference values exactly". That's strong evidence, not proof for every
  possible value, so the docs say "checked", not "guaranteed".

### Research (2026-11-08)

- **The standard, ECMA-262:** `+`, `−`, `×` and `÷` are exact (IEEE 754,
  round to nearest, ties to even), and so is `Math.sqrt`; `Math.pow`,
  `Math.exp`, `Math.log` and `Math.cbrt` are only
  "implementation-approximated". A number written in the source with 20
  or fewer significant digits is read exactly, and JavaScript and purs
  print at most 17.
- **The problem is real:** Firefox sent `Math.pow` through each
  platform's math library, and `Math.pow(Math.PI, -100)` came out 1 ULP
  off on older Android phones; that was fixed for Android only, and the
  bug notes that "Windows also has a less precise `std::pow`" (Bugzilla
  2037094; also 1775254). V8 has given `Math.pow(99, 99)` and `99 ** 99`
  different results (older reports), and projects that need identical
  results report Node and Chromium differing.
- **What exists:**
  - `@stdlib/math-base-special-pow` (npm, Apache-2.0): a JavaScript port
    of FreeBSD's `pow`, from Sun's fdlibm. Its source makes no `Math`
    call, only exact arithmetic, bit operations and `sqrt`, so it gives
    the same result in every engine by construction, accurate to under 1
    ULP. stdlib doesn't advertise that.
  - `decimal.js` (npm), wrapped by PureScript's `decimals`: pure
    JavaScript, so the same everywhere, but arbitrary-precision decimal
    objects, slow, and `decimals` makes its users install the npm
    package.
  - CRlibm and CORE-MATH, perfectly rounded and so the same everywhere:
    C libraries, with no JavaScript build found.
  - `deterministic` (npm) rewrites code, and calls itself early.
    fdlibm-js is a port with tests, not confirmed on npm or with `pow`.
- **PureScript** (the package set 81.11.4, 655 packages): `numbers`'
  `pow` is `Math.pow`; `precise`, `rationals`, `fixed-precision` and
  `bigints` do exact arithmetic, but by their names and descriptions none
  offers a power such as x^2.4 (their APIs not read in full).
- **What it means:** we need *the same* result everywhere, not the *most
  accurate*, and any code made only of exact operations gives that. The
  library can't use an npm package (it ships no JavaScript of its own,
  and its dependencies stay registry packages), so stdlib could serve
  the clients but not the library. sRGB's exponent is 2.4 = 12/5, so no
  general `pow` is needed: x^2.4 = x² × x^(2/5), which exact operations
  alone can compute.

### Values that aren't whole numbers

A table of 256 values covers every byte, and so every pixel the two
clients read. Other values occur too:

- **levels:** `evenRamp n` gives fractions for most counts: 127.5 for 3
  levels, 63.75, 127.5 and 191.25 for 5. Only counts n where n − 1
  divides 255 give whole numbers: 2, 4, 6, 16, 18, 52, 86 and 256. Today the
  CLI writes a level of 127.5 as 128, while the error was measured
  against 127.5;
- **a threshold,** such as `--threshold 96.5`: the CLI takes any number;
- **a library user's pixels,** a 16-bit picture scaled to 0–255, say;
- **the last resort's back conversion** (`quantize f`), for every
  corrected value.

All of them go through the two functions. Whether fractional levels
should be rounded to the byte that's written, so that the error is
measured against it, is a separate task (`TODO.md`, "Levels that aren't
whole numbers"): the mismatch exists today, without linear light.

## Decision 3: the nearest color or level

Settled 2026-11-09 for palettes, and extended to levels on 2026-11-10:
the nearest color or level is chosen by distance on stored values, while
the error stays in linear light; OKLab later. The rule: **a "nearest"
choice compares on stored values; amounts of light stay linear** (the
error, and ordered dithering's fraction between two levels).

**The problem:** in linear light, dark colors bunch up near zero. On the
0–255 scale, stored 0, 32 and 64 become 0, 3.7 and 13.1, while the step
from 192 to 255 becomes 121 wide, so plain RGB distance in linear light
barely sees the difference between two dark colors. On the C64 palette, a
dark blue (0, 0, 130) gets C64 blue (39, 36, 196) by distance on stored
values and by OKLab, but the dark grey (71, 71, 71) by distance in linear
light: the wrong hue.

**Measured** (2026-11-09) over 140,608 stored colors, every 5th value per
channel, with OKLab (Ottosson's published constants) as the perceptual
referee:

| Palette | Agrees with OKLab: stored | Agrees: linear | Perceptual distance to the choice, dark targets: stored | Same: linear |
|---|---:|---:|---:|---:|
| `websafe216` | 69.4% | 64.2% | 0.044 | 0.046 |
| `cga16` | 70.5% | 70.2% | 0.124 | 0.144 |
| `ansi16` | 62.7% | 61.1% | 0.199 | 0.272 |
| `c64` | 72.5% | 70.1% | 0.100 | 0.117 |
| `zx15` | 63.6% | 54.6% | 0.222 | 0.310 |
| `ansi256` | 65.5% | 70.7% | 0.060 | 0.059 |

Distance on stored values chooses closer to perception for 6 of the 7
palettes, most clearly among dark colors; only `ansi256` slightly prefers
linear light. Two caveats: OKLab as the referee would itself "win" by
construction, so this only ranks the two cheap options; and these are
single choices, not whole ditherings. With error diffusion, the error in
linear light keeps the tones right whatever is chosen; the choice decides
which dots are mixed, and so how noisy the result looks.

**The decision:**

- **Distance on stored values, the error in linear light.** The sRGB curve
  roughly follows how the eye sees lightness, which makes distance on
  stored values a cheap stand-in for perception, and it's today's choice.
  The quantizer converts the corrected value back to stored values for the
  comparison only, and outputs the chosen color in linear light:

  ```purescript
  nearestColor palette = quantizeLinear \enc ->
    let lights = map (toLinear enc) palette                         -- the outputs, once
    in \_ x -> lights at (nearestIndex palette (toStored enc x))    -- compared on stored values
  ```

  (`at` and `nearestIndex` are illustrative.)
- **`--palette` with `--kernel none` gives exactly today's picture:** the
  corrected value is then a table value, which the way back finds exactly.
- **The cost:** one back conversion per channel per pixel, about 36 ns
  each, small next to the palette search itself (`websafe216` takes about
  10 µs per pixel).
- **OKLab later,** as `TODO.md`'s item on CIELAB and OKLab distances: it
  chooses best, but it's a feature of its own, with its own verification.
  It needs two matrices and three cube roots per pixel, and the exact cube
  root of decision 2 makes those the same everywhere.
- **The cells' choice** for machine screens belongs to decision 5.

### Levels too (2026-11-10)

The same question for `--levels`, which picks the nearest level per
channel. Gray 130 has a perceptual lightness of 0.607, nearer to 170's
(0.738) than to 85's (0.450): stored values pick 170, rightly, and
linear light picks 85. Over the 256 grays, against the same referee:

| Levels | Agrees with OKLab: stored | Agrees: linear |
|---:|---:|---:|
| 2 | 228 / 256 | 168 / 256 |
| 3 | 235 / 256 | 194 / 256 |
| 4 | 239 / 256 | 207 / 256 |
| 6 | 243 / 256 | 222 / 256 |
| 8 | 241 / 256 | 227 / 256 |
| 16 | 250 / 256 | 245 / 256 |

- **Decisive: an exact check depends on it.** `--palette websafe216` and
  `--levels 6` give byte-identical files (check 1 in `check-cli.sh`, and
  a property in `PaletteSpec`), because the web-safe palette is the full
  6 × 6 × 6 cube, whose nearest color is each channel's nearest level, as
  long as both are measured the same way.
- **`--levels` without diffusion gives today's picture.** The visible
  change, the right tones, comes from the error in linear light.
- **No cost per pixel.** The nearer of two neighbouring levels on stored
  values is decided by their midpoint, and the curve keeps the order of
  values, so the midpoints are converted to linear light once, before the
  first pixel, and each pixel compares its linear value with them. Today's
  rule for exact ties, where the earlier level wins, carries over.
  Palettes have no such shortcut in three dimensions, so they keep the
  back conversion per pixel.
- **Unchanged:** ordered dithering picks its two levels and its fraction
  by light, since that's an amount of light; `threshold` is the same
  either way.

## Decision 4: the gray conversion

Settled 2026-11-10: luminance, sRGB's own weights on linear values, as the
final default; the opt-out keeps today's luma.

**Today:** `luma`, Rec. 601's weights (0.299 R + 0.587 G + 0.114 B) on
stored values, exact for neutral pixels. It's used by `--gray`, by the
gray pipeline (a threshold on a color picture), and by the web UI ("Turn
the picture gray first"), which copies the CLI's `luma`, `isNeutral` and
`toNeutral`.

**Measured** (2026-11-10), with OKLab lightness as the referee:

| Color | Its perceived lightness | Today (luma): gray, lightness | Luminance: gray, lightness |
|---|---:|---:|---:|
| red | 0.628 | 76, 0.417 | 127, 0.597 |
| green | 0.866 | 150, 0.672 | 220, 0.894 |
| blue | 0.452 | 29, 0.231 | 76, 0.416 |
| magenta | 0.702 | 105, 0.522 | 145, 0.658 |
| skin (224, 172, 140) | 0.784 | 184, 0.782 | 183, 0.779 |
| sky (120, 170, 230) | 0.726 | 162, 0.712 | 167, 0.727 |

Over 140,608 colors, today's luma misses the color's perceived lightness
by 0.047 on average, luminance by 0.015, and luminance is closer for 85%
of them. The gray moves by 13 steps on average, and by more than 20 for a
quarter of the colors, the saturated ones.

**The decision:**

- **Luminance, 0.2126 R + 0.7152 G + 0.0722 B on linear values, the final
  default.** The gray gives off as much light as the color, so the dots'
  average light matches it: an amount of light, which stays linear
  (decision 3's rule). It also keeps CIELAB's lightness, which depends
  only on luminance; the remaining 0.015 is where OKLab and CIELAB
  disagree, since OKLab also weighs hue and saturation, a goal of
  matching appearance. Saturated colors come out visibly lighter than
  today (pure blue 76 instead of 29); natural colors such as skin and sky
  barely change.
- **The opt-out keeps today's luma** (the user, 2026-11-10): it gives
  exactly today's pictures, as decision 1 promises, so the byte-for-byte
  check covers the color-to-gray configurations too; and luma on stored
  values is the classic conversion, for those who choose the old look.
- **One helper in the library,** chosen by the conversion (luminance with
  `srgb`, luma with `asStored`), used by both clients in place of their
  copies. How its output meets the drivers' conversion is a detail of the
  implementation.
- **Neutral pixels stay exactly as they are,** as today: the weights add
  up to 1, but in floating point the luminance of 79 of the 256 neutral
  grays isn't exactly their light (for today's luma, 65 of them). The
  logo's `--gray` inputs are gray, so the formula doesn't touch them.
- **OKLab lightness** at most as an option later, not a replacement:
  changing the default again would change every gray picture again.

## Exact checks

Expected to hold as they do today, to be confirmed by running them:

- an image made only of a palette's colors or of levels comes back
  unchanged, with any kernel (the same conversion on both sides, so the
  error is zero);
- `--palette websafe216` equals `--levels 6`, byte for byte (both choose
  on stored values, decision 3, so the cube's nearest color is still each
  channel's nearest level);
- a picture of valid machine cells comes back unchanged (the grays that
  decide the cells' order stay on the gray axis);
- a neutral pixel stays neutral where it does today.

New:

- with Floyd–Steinberg, a flat 128 gets about 21.6% white dots;
- with pure Bayer 8, a flat 128 gets exactly 14 of 64 white dots;
- the self-check passes in Node, Chromium, Firefox and WebKit.

## Open decisions

To settle one at a time; each leaning is only a starting point.

1. **The library's API:** settled, see [Decision
   1](#decision-1-the-librarys-api).
2. **Exactness across browsers:** settled, see [Decision
   2](#decision-2-exactness-across-browsers).
3. **The nearest color or level:** settled, see [Decision
   3](#decision-3-the-nearest-color-or-level).
4. **The gray conversion:** settled, see [Decision
   4](#decision-4-the-gray-conversion).
5. **Machine screens.** Artists of the time worked by eye, so the
   recommended 2×2 patterns may look different. Compare before keeping it
   on for them.
6. **The web UI's fit and background.** Do the area averaging and the
   flattening (decisions 22 and 27 in `web/ROADMAP.md`) also move to
   linear light?
7. **Names:** the twins' `…With` is settled (decision 1). Still open: the
   conversion's type and presets, their module, and the option that turns
   it off in the CLI and the web UI; the self-check's function, report
   and accessors (decision 2), and the CLI option that runs it.

## Plan

1. **Settle the open decisions** in this file.
2. **Library:** the conversions, machine cells included, with the new
   exact checks as properties; the self-check and its stored digest, run
   in Node by the tests; the gray helper (decision 4).
3. **CLI:** on by default, with the opt-out, and the self-check's mode;
   the gray helper in place of its `luma`, and `--gray`'s help text
   ("luma" no longer). The logo's script gets the opt-out, and
   `npm run logo` must then report every file unchanged.
4. **Web UI:** the same default and the switch, and the self-check in a
   worker of its own, with a notice; the gray helper in place of its
   copies. In the same branch as the CLI:
   `check:web` compares the page with the CLI, so the two change
   together, and it runs the self-check in the three browsers.
5. **Measure:** the benchmarks, a look at the test images, and the
   machine screens' recommendations again.
6. **Docs and release:** see below, then the release, and this file is
   deleted. The docs include how to write an efficient quantizer: with
   `quantizeLinear`, the coefficients converted in the outer `let`, once,
   not in the per-pixel function. In `quantizeLinear`'s doc comment, which
   Pursuit shows, and in the reference docs.

## Docs to update at the end

- `README.md`, "You need the best photo quality";
- `cli/README.md` and `web/README.md`, their limitations and options;
- `docs/ordered-dithering.md` (its formulas and exact properties),
  `docs/error-diffusion.md`, `docs/test-images.md`,
  `docs/machine-screens/README.md`;
- `TODO.md`: the item goes, with its "skews mid-tones slightly", and
  `web/ROADMAP.md`;
- `CHANGELOG.md`, `CLAUDE.md`.

## Sources

- Wikipedia, ["sRGB"](https://en.wikipedia.org/wiki/SRGB): the formula of
  IEC 61966-2-1 in both directions, and the weights 0.2126, 0.7152,
  0.0722.
- Wikipedia, ["DCI-P3"](https://en.wikipedia.org/wiki/DCI-P3): Display P3
  uses the sRGB curve.
- Wikipedia, ["Adobe RGB color
  space"](https://en.wikipedia.org/wiki/Adobe_RGB_color_space): a gamma of
  about 2.2.
- Wikipedia, ["RGB color
  spaces"](https://en.wikipedia.org/wiki/RGB_color_spaces): Apple RGB, 1.8.
- [ECMA-262](https://tc39.es/ecma262/), `Number::exponentiate`: an
  "implementation-approximated" value.
- S. K. Park and K. W. Miller's "minimal standard" generator (1988),
  with the multiplier 48271 they recommended in 1993, as in C++'s
  `std::minstd_rand` and the PureScript package `lcg` 4.0.1.
- The measurements and the prototype: scratch scripts, not kept in the
  repository.
