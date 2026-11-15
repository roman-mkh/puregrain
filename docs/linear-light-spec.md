# Spec: dithering in linear light

A working document (begun 2026-11-06, on the branch `linear-light`), the
specification for dithering in linear light in the library, the CLI and
the web UI. It's written so that anyone can implement it from here. After
the merge it's deleted: what lasts moves to the reference docs,
`CLAUDE.md` or `TODO.md`.

Read first: `CLAUDE.md` (the project's decisions and conventions) and
`CONTRIBUTING.md` (branches, checks, versions, releases).

**Status:** the architecture is settled, and so are all the [open
decisions](#open-decisions) (2026-11-12 to 14), written in here. Next is
the [plan](#plan)'s implementation. No code yet, and nothing here has
been prototyped except the measurements it quotes.

## The problem

The eye averages light, but dithering keeps the average of the stored
values, and stored sRGB values aren't proportional to light. Gray 128 has
only 21.6% of white's light, yet it gets about 50% white dots.

With 2 levels, a stored gray looks much lighter at 100% on an sRGB
screen: 32 looks like 99, 64 like 137, 128 like 188, 192 like 225. With
more levels the effect shrinks: 128 looks like 137 with 4 levels, and
like 131 with 6.

## Decided

- **A choice of curve, `--gamma`, off by default** (the user,
  2026-11-12; it replaces "on by default, with an option to turn it off"
  of 2026-10-21). Five values, the same in the CLI, the web UI and the
  library's presets:
  - `off`, the default (`1` and `1.0` too): no conversion, today's
    results bit for bit; the identity, not computed;
  - `1.2`, `1.5` and `1.8`: power curves, light = (byte / 255)^γ;
  - `srgb`: linear light, the standard's curve.

  "Gamma" here doesn't adjust the picture, as an editor's gamma slider
  does: it says how the screen turns numbers into light, and the
  dithering keeps that light. Its docs get a page of their own.
- **Why off by default** (measured 2026-11-10 and 11 on the gray
  composite and the machine screens, with scratch scripts, and judged by
  the user):
  - Linear light gives the right brightness only where the dots reach the
    eye as they are: at 1:1, and from a distance. Views that scale with
    smoothing (HiDPI screens, phones, pictures fitted into a page)
    average the stored values, and there today's dithering looks right
    and linear light too dark. The user's own view behaved like a gamma
    between 1.0 and 1.5 (a chart of line patches, half of white's light,
    in fields of gray), and there gamma 1.5 looked closest to the
    original.
  - Dark tones turn black as the gamma rises, in the file, so on any
    screen: a Bayer map or Atkinson can't place a dot below some gray.
    Flat grays come out all black up to:

    | Gamma | Half the light at byte | Bayer 2 | Bayer 4 | Atkinson |
    |---|---:|---:|---:|---:|
    | off | 127.5 | 31 | 7 | 32 |
    | 1.2 | 143.1 | 45 | 14 | 40 |
    | 1.5 | 160.6 | 63 | 25 | 50 |
    | 1.8 | 173.5 | 80 | 37 | 59 |
    | srgb | 187.5 | 99 | 49 | 65 |

    Floyd–Steinberg, and every kernel but Atkinson, loses none at any
    gamma: they pass all the error on, so every gray above 0 gets dots.
- **Recommended:** `off` for machine screens (the look of the time, and
  Bayer 2's dark tones) and with Atkinson; `srgb` for pictures seen at
  1:1 from a distance; the values between to taste. The default may be
  revisited, perhaps per target, once the user has tried the web UI on
  other monitors and pictures (2026-11-12).
- **When:** after the web UI's v2, before v3 (2026-10-21). The web UI gets
  the same five values.
- **Every picture counts as sRGB** (2026-11-06). Neither client reads
  color profiles: both dither the stored numbers, the web UI on purpose,
  so that its results match the CLI's. With `srgb`, a Display P3 picture,
  which has the same curve, gets its light right, and its colors are as
  slightly off as they are today. Adobe RGB (a curve of about 2.2) and
  Apple RGB (1.8) come out a little off in brightness too. The docs state
  it as a limit; converting profiles would be a separate feature.
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
- **What's written must come back as whole bytes:** `Zx.toScr` and the
  C64's writers compare each pixel with its cell's colors exactly. The
  way back finds each target's byte in the table (decision 2, "The five
  curves"), so it's exact by construction. Rounding the formula's result
  also brought all 256 bytes back for `srgb` (tested 2026-11-06), but a
  level that isn't a byte could round the other way.

## Decision 1: the library's API

Settled 2026-11-08; amended 2026-11-12 for the gamma (see
[Decided](#decided)): no conversion by default, five presets, and
nothing breaks, so the release is 0.2.2. The conversion is the driver's
choice, not the quantizer's: it describes the picture, how its numbers
relate to light.

- **One value holds both directions,** so they can't be mismatched. Five
  presets, as `--gamma`'s values: `asStored` (`off`, the default: today's
  behaviour, the identity both ways), the power curves of 1.2, 1.5 and
  1.8, and `srgb`. No constructor for other curves for now (2026-11-14,
  start closed): nothing needs one, and the self-check couldn't vouch for
  its curves. If one comes, it checks its two functions as `fromOffsets`
  checks kernels: each other's inverse, rising steadily, and keeping 0 as
  0 and 255 as 255 (`threshold` outputs exactly those, and the machines'
  files need their colors back exactly).
- **The drivers convert nothing by default,** and keep their names,
  arguments and types: `ditherImage`, `ditherRows`, `initDithering`,
  `ditherCells` and `ditherBands` give today's pictures from the same
  code. Each has a twin that takes the conversion first:
  `ditherImageWith`, `ditherRowsWith`, `initDitheringWith`,
  `ditherCellsWith` and `ditherBandsWith`. `ditherRow` needs none, since
  the stepper's state holds the conversion. The internal
  `ditherImageWith` and `ditherRowsWith` of `Puregrain.Internal.Image`
  get other names.
- **`Quantize` takes the conversion from the driver,** as ready-made
  functions: one pair for the pixel type, and the curve itself, for
  single channels (`perChannel`'s scalar quantizers). It's opaque, so
  its inside can change, and callers still write `threshold 128.0`. The
  driver passes the conversion once, before the first pixel, and keeps
  the resulting function: passed per pixel, the targets would be
  converted again for every pixel, since PureScript shares nothing by
  itself. The cells' quantizer and palettes work the same way.
- **Only the twins need one more constraint,** to convert channel by
  channel: `ColorChannels`, a class of its own (sub-step 2b, the user's
  agreement 2026-11-14), since `MapChannels` maps alpha too, which
  `perChannel` needs, but `RGBA`'s alpha isn't on any light curve and
  must not be converted. The default drivers convert nothing, and
  `quantize` and `quantizeWith` get the conversion as functions, so none
  of them needs it: a pixel type of the caller's own, with `Ring` and
  `Scalable` but neither class, works as before. (The code below still
  writes `MapChannels` for it.)
- **Release 0.2.2, a compatible change** (amended 2026-11-12, from 0.3.0;
  the rules in `CONTRIBUTING.md`): the same code gives the same pictures,
  and every existing signature still compiles. The renamed internal
  `ditherImageWith` and `ditherRowsWith` are in `Puregrain.Internal.*`,
  documented as unstable.
- **Pinned by tests:** the default drivers and `…With asStored` equal the
  test reference, as `ditherImage` does today. Before the merge, the
  CLI's default, `--gamma off`, must give today's files byte for byte
  for a set of configurations, as the reshape of 2026-10-04 was checked.

```purescript
-- both directions, per channel, on the 0–255 scale (opaque)
data Encoding
asStored :: Encoding                          -- off: the identity, the default
gamma12, gamma15, gamma18, srgb :: Encoding

-- applying it to a pixel, a level or a color, channel by channel
toLinear :: forall a. MapChannels a => Encoding -> a -> a
toStored :: forall a. MapChannels a => Encoding -> a -> a

-- what a driver hands the quantizer (internal)
type Conversion a = { toLinear :: a -> a, toStored :: a -> a, curve :: Encoding }
noConversion  :: forall a. Conversion a       -- the identity, curve asStored
conversionFor :: forall a. MapChannels a => Encoding -> Conversion a

ditherImage                                   -- unchanged: no new constraint
  :: forall a. Ring a => Scalable a
  => Kernel -> Quantize a -> Array (Array a) -> Array (Array a)
ditherImage = ditherImageVia noConversion

ditherImageWith
  :: forall a. Ring a => Scalable a => MapChannels a
  => Encoding -> Kernel -> Quantize a -> Array (Array a) -> Array (Array a)
ditherImageWith enc = ditherImageVia (conversionFor enc)
```

`Encoding`, its presets, `toLinear` and `toStored` are placeholders,
named in [decision 7](#decision-7-names) (`Gamma`, `gammaOff` …,
`toLight`, `fromLight`). `Conversion`, `noConversion`, `conversionFor`
and `ditherImageVia` are internal.

**As built** (sub-step 2d, 2026-11-14): `Quantize` moved to
`Puregrain.Internal.Quantize`, which `Puregrain.Quantize` re-exports
opaquely; `Conversion` (with the curve under `gamma`), `noConversion` and
`conversionFor` are in `Puregrain.Internal.Gamma`; the internal drivers
are `ditherImageVia` and `ditherRowsVia`, the queue backend first; the
core takes the quantizer resolved once per run, and `quantize` and
`quantizeWith` check the gamma once, so with `gammaOff` they're exactly
today's functions. The public twins, `quantizeInLight` and
`runQuantizeWith` come in 2e with the presets (the user, 2026-11-14): a
twin gives right results only once the presets convert their targets.
No result changed: every test, 21 CLI configurations byte for byte, and
`check:cli`.

### Custom quantizers and `runQuantize`

`Quantize` gets the conversion from the driver, once, before the first
pixel:

```purescript
-- inside the library; opaque, as today
newtype Quantize a = Quantize (Conversion a -> Context -> a -> a)
```

The driver gets the per-pixel function the same way for every
quantizer, once per run, through an internal function (`quantizerFor`,
the name agreed with the user):

```purescript
quantizerFor :: forall a. Conversion a -> Quantize a -> Context -> a -> a
quantizerFor conv (Quantize q) = q conv
```

`perChannel` hands its scalar quantizer a conversion made from the
curve (`conv.curve`), which is why the curve comes along.

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
quantizeLinear f = Quantize \conv -> f conv.curve

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

**Values kept as they are** (2026-11-14): a quantizer built with
`quantizeLinear` that ignores the curve it's handed takes its numbers as
they are, in whatever space the driver dithers in: bytes with `asStored`,
light with any curve. That's the author's responsibility, and what's
written then comes back through the formula, so the file's values are
exact only where the numbers are the light of whole bytes. Numbers made
for one curve are converted for another with `toLinear` and `toStored`,
once, before the first pixel. No flag or tag on `Quantize` for either
case (the user, 2026-11-14): a mismatch found by a tag could only crash,
since the drivers have no error channel.

**The last resort: `quantize f` and `quantizeWith f`,** for an `f` whose
coefficients the library can't see. `f` keeps its meaning, stored values
in and out, as the docs say today: the library converts each pixel back
to stored before `f`, and `f`'s result to linear after it. That's `imap`
from `Invariant`, a line inside the library, with no new dependency and
nothing for the author to implement. The error still stays in linear
light, so with any kernel the tones come out right, and without
diffusion `f` decides as today. The price: both directions for every
pixel, so it's slower, and decision 2's exactness question applies.
Neither constructor needs a new constraint, since the driver hands them
the conversion as functions:

```purescript
quantize :: forall a. (a -> a) -> Quantize a                -- unchanged type
quantize f = Quantize \conv _ x -> conv.toLinear (f (conv.toStored x))
```

**`runQuantize` answers for a stored value:** it converts nothing by
default, so it's today's `runQuantize`, and `runQuantizeWith` takes the
conversion. Both are built on `quantizerFor`:

```purescript
runQuantizeWith :: forall a. MapChannels a => Encoding -> Quantize a -> Context -> a -> a
runQuantizeWith enc q ctx v = toStored enc (quantizerFor (conversionFor enc) q ctx (toLinear enc v))

runQuantize :: forall a. Quantize a -> Context -> a -> a   -- unchanged type
runQuantize = quantizerFor noConversion
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
  input gave a smaller result, in either direction. (Neighbouring
  numbers can, by up to two units in the last place, found in sub-step
  2a: see `docs/exact-arithmetic.md`. Random values almost never land
  next to each other.)
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
diagnosis. The names are placeholders, named in [decision
7](#decision-7-names) (`checkEngine`, `EngineReport`), which also gives
the self-check a module of its own, `Puregrain.SelfCheck`, and the exact
roots `Puregrain.Internal.Exact`.

**As built** (sub-step 2c, 2026-11-14; the user agreed to the two
changes): the four computed curves, both ways; 200,000 generator values
per curve, not in all; and **eight stored digests, one per curve and
direction,** in place of one, so that a failure names its curve and
direction ("gammaSrgb, back: the results differ from the reference")
rather than "the first value" (which would need every reference value
stored). A second check needs no reference: every byte back exactly from
its light, naming the byte. It takes about 0.45 s in Node 22 and 0.43
to 0.61 s in the browsers, and gave the same eight digests in Node 22.14
and 26.13, Chromium 156, Firefox 157 and WebKit 27.2. Details in
`docs/exact-arithmetic.md`, "The engine self-check". The bullets below
were written before; where they differ (one constant, 20 ms), this
paragraph holds.

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
- **No native path** (the user's question, 2026-11-14): even on an
  engine whose `Math.pow` matched the digest, the library keeps its own
  roots. The standard lets native functions differ between engines
  (Node 22's `Math.pow` and the browsers' differ on about 10% of values),
  and our roots aren't always the correctly rounded value either, so a
  native function would practically never match. A match would also
  prove less: only the exact operations are the same everywhere by the
  standard, so agreeing on the samples says little about other values.
  And there's nothing to gain: pixels and targets go through the table,
  and the formula runs only for the palette comparison, about 150 to
  270 ns per channel with the library's roots (decision 3, "The cost").

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

### The five curves (2026-11-12)

`--gamma`'s values (see [Decided](#decided)), each built from exact
operations only, as the prototype's sRGB curve is. Written in sub-step
2b (`Puregrain.Gamma`, `Puregrain.Internal.Gamma`; measurements and
tests in `docs/exact-arithmetic.md`, "The light curves"). On the 0–1
scale, x is a stored value and L its light:

| Curve | To light | Back |
|---|---|---|
| `off` | x, not computed | L, not computed |
| 1.2 | x · ⁵√x | √L · ∛L |
| 1.5 | x · √x | (∛L)² |
| 1.8 | x · (⁵√x)⁴ | (∛(∛L))⁵ |
| `srgb` | the prototype's | the prototype's |

- **The roots** (written in sub-step 2a, `Puregrain.Internal.Exact`; why
  and how in `docs/exact-arithmetic.md`): the square root, exact by
  ECMA-262, and the fifth and cube roots, reduced into [1/32, 1) and
  [1/8, 1) by exact powers of 2, then 10 and 9 of Newton's steps from 1
  (at most 9 and 8 measured, plus one of margin). The same counts fit
  every input, near 0 included, so the pure powers need no start of
  their own. The results are within two units in the last place of the
  nearest number, mostly that number itself: two neighbouring inputs can
  get roots up to two units apart in either order, which no comparison
  in the dithering meets (the user, 2026-11-14).
- **Negative values are mirrored,** f(−x) = −f(x), for every curve, as
  the W3C's sample code (CSS Color 4) extends sRGB's (the user,
  2026-11-12). Only the way back meets them: error diffusion pushes
  corrected values below 0 in dark areas, and decision 3's palette
  comparison converts them. The prototype's `srgb` continued its straight
  piece below 0; the mirror replaces that, one rule for every curve.
  Values above 255 need nothing: the powers work there as they are.
- **Each curve keeps one table** of 256 light values, built when it's
  first used, not when its module loads (a top-level value would be
  computed at every start, `--help` included): the CLI builds it once
  per run, the web UI's worker once per change of the gamma.
- **What's written goes back through the table, not the formula.** The
  light value of a target, a palette color, a machine color or a level,
  is one of the table's entries, so the way back finds its byte exactly:
  no rounding can make a color the palette doesn't have, and the library
  returns exactly 85, not 85.00000000000001. The palette comparison
  (decision 3) goes back the same way, table first (sub-step 2e, agreed
  with the user 2026-11-14; at first this note said "formula only"): a
  pixel that's exactly a byte's light comes back as that byte, so a
  palette without diffusion gives today's picture. The formula serves
  only the values that aren't a byte's light.
- **A level that isn't a byte** (127.5 for 3 levels) is rounded to one
  first when a curve is chosen, so that it's a table entry too: through
  the formula, 127.5 could come back as 127.49999999999999 and be written
  as 127, not today's 128. With `off` nothing changes; `TODO.md`'s item
  on such levels covers `off` later, in a minor release, since it changes
  pictures.
- **The self-check covers the four computed curves** (`srgb`, 1.2, 1.5
  and 1.8) in its one stored digest; `off` needs none.

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
- **The cost:** one back conversion per channel per pixel, small next to
  the palette search itself (`websafe216` takes about 10 µs per pixel).
  The prototype's formula took about 36 ns; the library's, built on
  `Puregrain.Internal.Exact`'s roots, takes about 150 ns per channel for
  `srgb`, 1.2 and 1.5 and 270 ns for 1.8, which needs two cube roots
  (measured 2026-11-14, after the roots were specialized): about 0.5 µs
  per RGB pixel, and only with a curve other than `gammaOff`.
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

### Under any gamma (2026-11-12)

The rule holds for every curve: choices on stored values, amounts of
light in the curve's light.

- **`threshold N` keeps N a stored value,** converted to the curve's
  light once, so `--threshold 100` cuts at the same gray under every
  gamma, as in any image editor.
- **A cut at half of white's light instead** (the user's question,
  2026-11-11), measured with `srgb`, black and white, on the gray
  composite, against the converted 128:

  | | Floyd–Steinberg: converted / half | Atkinson: converted / half |
  |---|---|---|
  | Light given off (the original: 37.8%) | 37.9% / 37.8% | 42.3% / 37.3% |
  | Difference from the original, blurred in light (RMS) | 1.62% / 1.59% | 8.01% / 5.60% |
  | Flat grays all black up to | 3 / 7 | 65 / 99 |

  (The blur: Gaussian, 1.5 pixels, on both pictures' light.) For
  Floyd–Steinberg, which passes all the error on, the cut hardly matters.
  Atkinson drops a quarter of every error, and with the converted cut the
  errors are lopsided (a white dot leaves up to −200, a black one at most
  +55), so it keeps light it shouldn't: the picture comes out too bright.
  The cut at half keeps its light right, but turns more dark tones black,
  and it would make `--threshold N` cut at another gray under each gamma.
- **Kept: the converted cut** (the user, 2026-11-12), and the docs
  recommend `off` with Atkinson, whose dropped error is a trick made for
  stored values.

### Levels even in light? (2026-11-13)

The user's question: in linear light, equal steps are equal steps of
light, so should `--levels` spread its levels evenly in light, and cut
between them halfway in light? Measured with `srgb` and 4 levels on the
composites, in three variants, the error in light in all three:

- **(a) decision 3:** the levels even in bytes, 0, 85, 170 and 255 (in
  light 0, 23.2, 102.5 and 255), cut at the sRGB midpoints converted
  (6.0, 54.6 and 168.8 in light);
- **(b)** the same levels, cut halfway in light (11.6, 62.8 and 178.8);
- **(c)** the levels even in light, 0, 85, 170 and 255 in light, which
  are written as the bytes 0, 156, 213 and 255, cut halfway in light.

| | Gray, Floyd–Steinberg: error in L* | Color, Floyd–Steinberg: ΔE, whole / sphere | Color, Atkinson: ΔE, whole / sphere |
|---|---:|---:|---:|
| (a) | 0.88 | 1.56 / 1.96 | 4.18 / 3.72 |
| (b) | 0.83 | 1.62 / 2.07 | 5.06 / 5.27 |
| (c) | 1.79 | 3.49 / 6.02 | 9.27 / 15.27 |

(Both pictures blurred in light, Gaussian, 1.5 pixels, then compared as
CIE L* for gray and as CIELAB ΔE 1976 for color; RMS. With
Floyd–Steinberg all three give off the original's light within 0.1
points.)

- **Levels even in light look uneven:** their L* is 0, 64, 85 and 100,
  against 0, 36, 70 and 100 for levels even in bytes. The first step
  covers almost two thirds of the way to white, so shadows get sparse
  light dots on black, in color specks of single channels. sRGB spaces
  its values so that equal steps look roughly equal, the same reason
  pictures are stored in sRGB, not in light.
- **(a) against (b):** a wash with Floyd–Steinberg ((b) a little ahead in
  gray, behind in color); with Atkinson, which drops error, (a) clearly
  ahead. The user's eye agreed, from 4 m: (a) best.
- **Kept** (the user, 2026-11-13): levels and thresholds always in sRGB
  bytes. With a curve, the levels and the cut points (the sRGB
  midpoints, and a threshold) are converted to its light, and the error
  stays in light; what's written is each level's own byte.
- **An idea, not planned:** explicit levels, `--levels a,b,c`, always
  bytes, under every gamma. They'd also reach levels even in light
  (`--levels 0,156,213,255`) without a mode of their own.

### As built (sub-step 2e, 2026-11-14)

- **`threshold`, `nearestLevel` and `ordered`** are built with
  `quantizeInLight`: the threshold, the levels and the cut points are
  converted once per image. `nearestLevel` keeps its scan with
  `gammaOff`, and with a curve compares with the sRGB midpoints between
  the sorted levels, converted to light; on an exact tie the level given
  earlier wins, as with the scan.
- **`nearestColor` needed no change:** it's built with `quantize`, whose
  wrapper (sub-step 2d) brings each pixel back with `fromLight`, table
  first, compares on stored values, and takes the chosen color to light
  through the table. That's this decision's rule as it stands.
- **Pinned by properties** under every curve (`InLightSpec`), besides
  `gammaOff` giving the plain drivers' rows: an independent reference on
  rows taken to light and back; the stream and the stepper; pictures made
  only of levels or colors coming back unchanged; `websafe216` equal to
  `--levels 6`; no diffusion giving `ditherImage`'s picture for
  `threshold`, `nearestLevel` and palettes; only rounded levels and
  palette colors as outputs; with `gammaSrgb`, a flat 128 at about 21.6%
  white with Floyd–Steinberg and 14 of 64 with the 8×8 Bayer map. Cut
  points at the midpoints in light instead failed 9 of them.
- **Fixed 2026-11-15:** with a level given twice, a tie at a midpoint
  was decided by the later copy's place: levels [35, 143, 35] gave 143
  for 89, the plain scan 35. Found by the "without diffusion" property on
  a new seed (182268069) during step 4a's checks. Of equal levels, given
  twice or made equal by rounding, only the one given first is kept now;
  a test pins the four orders under every curve, and fails without the
  fix.

## Decision 4: the gray conversion

Settled 2026-11-10; amended 2026-11-12 for the gamma: luminance, sRGB's
own weights, on the light of any curve but `off`; `off`, the default,
keeps today's luma.

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

- **Luminance, 0.2126 R + 0.7152 G + 0.0722 B, on the curve's light,**
  with every curve but `off` (its weights are linear light's; on 1.2 to
  1.8 they're used as they are). With `srgb`, the gray gives off as much
  light as the color, so the dots'
  average light matches it: an amount of light, which stays linear
  (decision 3's rule). It also keeps CIELAB's lightness, which depends
  only on luminance; the remaining 0.015 is where OKLab and CIELAB
  disagree, since OKLab also weighs hue and saturation, a goal of
  matching appearance. Saturated colors come out visibly lighter than
  today (pure blue 76 instead of 29); natural colors such as skin and sky
  barely change.
- **`off` keeps today's luma** (the user, 2026-11-10): it gives exactly
  today's pictures, as decision 1 promises, so the byte-for-byte check
  covers the color-to-gray configurations too; and luma on stored values
  is the classic conversion, for those who choose the old look.
- **One helper in the library,** chosen by the conversion (luma with
  `asStored`, luminance on the curve's light with any other), used by
  both clients in place of their copies. How its output meets the
  drivers' conversion is a detail of the implementation.
- **Neutral pixels stay exactly as they are,** as today: the weights add
  up to 1, but in floating point the luminance of 79 of the 256 neutral
  grays isn't exactly their light (for today's luma, 65 of them). The
  logo's `--gray` inputs are gray, so the formula doesn't touch them.
- **OKLab lightness** at most as an option later, not a replacement:
  changing the default again would change every gray picture again.

### As built (sub-step 2g, 2026-11-14)

- **`toGray :: Gamma -> RGB -> Number`** in `Puregrain.Gamma`, also in
  the facade (the name agreed with the user). A neutral color gives its
  own value under every gamma; `gammaOff` gives luma as the CLI and the
  web UI compute it, in the same order of operations; a curve gives
  0.2126 R + 0.7152 G + 0.0722 B on the channels' light, brought back
  with `fromLight` (table first).
- **A stored value, not light** (agreed): it works with every driver as
  it is, and with `RGB v v v` for the color pipelines after "gray
  first". The price, measured with `gammaSrgb` in Node on a million
  colors: the luminance takes 140 ns per pixel, and going back to a
  stored value and the driver taking it to light again about 550 ns
  more, roughly a quarter of gray dithering's time; only for color
  pictures dithered in gray under a curve. Step 5 measures it on real
  pictures; faster roots (the same results) or a light path (more API)
  are the remedies if it matters.
- **The round trip** comes back to the luminance exactly for 9% (1.8) to
  44% (1.2) of colors, otherwise within 21 units in the last place
  (1.8; sRGB 10, 1.5 7, 1.2 5), at most 2.6 × 10⁻¹⁵ of the light
  (636,000 colors per curve).
- **Exact operations only** (the curves, then + and ×), so the same on
  every engine; the self-check needs no new digest.
- **Pinned by properties** (`GammaSpec`): `gammaOff` equal to a copy of
  today's luma; the 256 neutral grays (and random neutral values) exact
  under every gamma; never darker when a channel rises; under every
  curve, the gray's light the color's by the `pow` definition within
  10⁻¹², and through the library's own conversion within 10⁻¹⁴; and this
  decision's table, rounded, with `gammaOff` and `gammaSrgb`. Mutations:
  luma's weights under a curve failed 9 tests, the neutral case dropped
  1 (the neutral test).
- **The clients** keep their `luma` until steps 3 and 4, which replace it
  with `toGray`; `isNeutral` and `toNeutral` stay theirs.

## Decision 5: machine screens

Settled 2026-11-12: nothing special. Machine screens take `--gamma` like
everything else, with the same default, `off`, and the same rules:

1. **Each cell's two colors** are chosen from the original pixels, on
   stored values: which pair fits best is a choice (decision 3).
2. **Inside the cell,** Bayer's fraction between the cell's two colors is
   an amount of light, measured in the curve's light; with a kernel, the
   nearer of the two is a choice, compared on stored values.
3. **The error** stays in the curve's light.

- **Exact under every curve:** a picture made only of valid cells comes
  back unchanged (the choice finds its pair with a score of 0, every
  pixel is one of its colors, every error is 0), and the files get the
  machine's own bytes, through the table (decision 2).
- **Measured** (2026-11-10; the cells chosen by the library, the rest
  emulated, which gave today's CLI output exactly with no conversion):
  with linear light, the ZX Spectrum's Bayer 2 lost the grays around the
  sphere (the user: "no go"), its Bayer 4 looked better, and the C64's
  screens barely changed, coming out a little closer to the original.
- **Recommended:** `off` for machine screens, the look of the time (see
  [Decided](#decided)); the docs mention `srgb` with Bayer 4 for photos,
  as something to try.

### As built (sub-step 2f, 2026-11-14)

- **`ditherCellsWith` and `ditherBandsWith`** in `Puregrain.Cells`, the
  twins of `ditherCells` and `ditherBands`, which convert nothing and give
  today's results (the 21 CLI outputs byte for byte).
- **The cells** are chosen from the stored rows, as before. Each band's
  rows then go to light on the way in and back on the way out, as in the
  drivers (sub-step 2d). `orderedInCell` takes the band's cell colors to
  light once per band; `nearestInCell` brings each pixel back (table
  first), picks the nearer color on stored values, and takes it to light
  through the table.
- **Exact when the cells' colors are whole bytes,** as every machine's
  are: through the table, each comes back as its own byte. Colors that
  aren't whole numbers, possible with a hand-made `CellMode`, go through
  the formulas and may come back a unit in the last place off; the doc
  comment promises exactness only for bytes.
- **Pinned by properties** under every curve: `gammaOff` giving the plain
  functions' results; the same cells; every pixel one of its cell's
  colors (byte colors); the stream equal to memory; `nearestInCell`
  without diffusion giving `ditherCells`'s picture; `orderedInCell`
  without diffusion following an independent per-pixel rule in light;
  ZX Spectrum and C64 pictures of valid cells unchanged, with any kernel
  and rule (`ZxSpectrumSpec`, `C64Spec`); and with `gammaSrgb`, `toScr`
  and `toHiresPrg` accepting the result, and a flat 128 between black and
  white (216) getting one white dot in four from the 2×2 Bayer map, not
  two. Mutations: comparing `nearestInCell` in light failed the
  no-diffusion property under all four curves; measuring `orderedInCell`
  on stored values failed the light property under all four, and the
  example.

## Decision 6: the web UI's fit and background

Settled 2026-11-12: both follow the chosen curve. With `off` they stay as
they are; with another curve, the fit's area averaging (decision 22 in
`web/ROADMAP.md`) and the flattening of transparent parts (decision 27)
mix in the curve's light, and each result goes back to a byte, so that
the CLI dithers the same picture.

- **Why:** one setting says how numbers become light, and every step that
  mixes colors uses it, or one step undoes another. Fine black and white
  lines shrunk 2× for the ZX Spectrum's screen: averaged as stored values
  they become gray 128, which `srgb` dithers to 22% white dots; averaged
  in light, gray 188, dithered to 50%, the lines' own brightness. Half-
  transparent black over white gives 128 or 188 the same way.
- **Shared:** the flattening becomes the library helper that the CLI's
  planned `--background` uses too (`TODO.md`), with the same rule; a
  later `--fit` in the CLI would follow it as well.
- **Exact:** today's fit is exact through whole-number weights; in light
  it sums table values in a fixed order, the same on every engine, and
  goes back through the exact way back before rounding.

## Decision 7: names

Settled 2026-11-12 for the clients and 2026-11-14 for the library.

- **The option is `--gamma`,** with `off` (the default; `1` and `1.0`
  mean the same), `1.2`, `1.5`, `1.8` and `srgb`. It replaces
  `--linear-light on|off`, agreed on 2026-11-10 and never written in.
  `off`, because in color management "gamma 1.0" means the values already
  are linear light, so `--gamma 1.0` alone could be read as linear light,
  the opposite of what it does.
- **"Gamma"** is the usual word. Strictly, sRGB's curve is a transfer
  function, a straight piece and a power, but Wikipedia's sRGB article
  heads it "Transfer function ("gamma")". The docs' first sentence says
  it doesn't adjust the picture.
- **The web UI** offers the same five values. The (i) text comes with
  v3's (i) for every setting, a task of its own.
- **The library's names** replace the placeholders of decisions 1 and 2,
  which keep them, so that their reasoning reads as it was written:

  | Placeholder | Name |
  |---|---|
  | `Encoding` | `Gamma` |
  | `asStored`, the curves of 1.2, 1.5 and 1.8, `srgb` | `gammaOff`, `gamma1p2`, `gamma1p5`, `gamma1p8`, `gammaSrgb` |
  | `toLinear`, `toStored` | `toLight`, `fromLight` |
  | `quantizeLinear` | `quantizeInLight` |
  | `encoding`, the checked constructor for other curves | none for now (decision 1) |
  | `checkPlatform`, `PlatformReport` | `checkEngine`, `EngineReport` |
  | `exactArithmetic`, `problems` | kept |
  | the CLI's mode for the self-check | `--check-engine` |

  "p" stands for the point, as in names such as `v1p2`: a name can't
  hold a dot (the compiler rejects `gamma1.2` and `gamma1·2`), the user
  didn't want underscores, and look-alike Unicode letters would compile
  but couldn't be typed or searched, the reason the project keeps code to
  the ASCII hyphen. "Engine" in `checkEngine` is the JavaScript engine
  (V8, SpiderMonkey, JavaScriptCore): its arithmetic and its optimizing
  compiler, as the doc comment says. The twins' `…With` and the internal
  `quantizerFor` were settled in decision 1.
- **Modules:**
  - `Puregrain.Gamma`: `Gamma`, the five presets, `toLight` and
    `fromLight`; the curves' inside in `Puregrain.Internal.Gamma`;
  - `quantizeInLight` and `runQuantizeWith` in `Puregrain.Quantize`,
    next to `quantize`, `quantizeWith` and `runQuantize`;
  - `Puregrain.SelfCheck`: `checkEngine`, `EngineReport`,
    `exactArithmetic` and `problems`. A module of its own, not
    `Puregrain.Gamma`, since it checks the engine's arithmetic, which
    OKLab's distance (`TODO.md`) would use too, joining the same report;
    moved later, it would break users' imports. Not `Puregrain.Engine…`:
    the project already calls its dithering core "the engine";
  - the exact roots in `Puregrain.Internal.Exact`, used by
    `Puregrain.Internal.Gamma` now and by OKLab later.
- **The facade** (`Puregrain`) re-exports `Gamma`, the five presets and
  the `…With` twins, which a typical application needs. `toLight`,
  `fromLight`, `quantizeInLight` and the self-check are building blocks
  and stay in their modules, as `compilePalette` does.

## Exact checks

Expected to hold under every curve, as they do today, to be confirmed by
running them:

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

- with `off`, every result is today's, byte for byte;
- with `srgb` and Floyd–Steinberg, a flat 128 gets about 21.6% white
  dots;
- with `srgb` and pure Bayer 8, a flat 128 gets exactly 14 of 64 white
  dots;
- every target comes back as its own byte under every curve;
- the self-check passes in Node, Chromium, Firefox and WebKit.

## Open decisions

All seven are settled (2026-11-12 to 14), with the gamma's amendments to
decisions 1 to 4.

1. **The library's API:** settled, see [Decision
   1](#decision-1-the-librarys-api).
2. **Exactness across browsers:** settled, see [Decision
   2](#decision-2-exactness-across-browsers).
3. **The nearest color or level:** settled, see [Decision
   3](#decision-3-the-nearest-color-or-level).
4. **The gray conversion:** settled, see [Decision
   4](#decision-4-the-gray-conversion).
5. **Machine screens:** settled, see [Decision
   5](#decision-5-machine-screens).
6. **The web UI's fit and background:** settled, see [Decision
   6](#decision-6-the-web-uis-fit-and-background).
7. **Names:** settled, see [Decision 7](#decision-7-names).

## Measured, as built (step 5, 2026-11-15)

`node scripts/measure-gamma.mjs` (after `npm run build`) dithers the test
images through the real CLI under each gamma and measures the results.
The tables below are its output; it leaves the pictures in
`samples/gamma/` (gitignored). The measure is the one of "Levels even in
light?" above: both pictures blurred (Gaussian, 1.5 pixels), then
compared as CIE L* for gray and as CIELAB ΔE 1976 for color, RMS. With a
second view, since the pictures are seen in two ways:

- **light:** the blur averages the pixels' light, as the eye does at 1:1
  from a distance, the dots reaching it as they are;
- **stored:** the blur averages the stored values, as a scaler that
  smooths does (HiDPI screens, phones, a picture fitted into a page),
  and the average is then shown through sRGB's curve.

Both take sRGB's curve as the screen, whatever the gamma of the
dithering: the gamma says what the dithering keeps, not what the screen
is.

**It reproduces the emulation of November 10 to 13.** All 15 values of
the flat grays equal the table of "Decided". The original's light is
37.8% and Floyd–Steinberg under sRGB gives off 37.9%, as before. The
color composite under sRGB gives ΔE 1.58 / 1.95 for Floyd–Steinberg and
4.18 / 3.65 for Atkinson, against the 1.56 / 1.96 and 4.18 / 3.72
measured then, and the gray composite's L* error 0.90 against 0.88:
within 3%.

**Flat grays that come out all black** (the largest byte, at 64 × 64; Floyd–Steinberg and every kernel but Atkinson lose none):

| Gamma | Half the light at byte | Bayer 2 | Bayer 4 | Atkinson |
| :--- | ---: | ---: | ---: | ---: |
| off | 127.5 | 31 | 7 | 32 |
| 1.2 | 143.1 | 45 | 14 | 40 |
| 1.5 | 160.6 | 63 | 25 | 50 |
| 1.8 | 173.5 | 80 | 37 | 59 |
| sRGB | 187.5 | 99 | 49 | 65 |

**The gray composite, black and white** (512²; error in L* after blurring, RMS, as: viewed in light / viewed on stored values):

| Gamma | Floyd–Steinberg | Atkinson | Bayer 2 | Bayer 4 | 4 levels, Floyd–Steinberg |
| :--- | ---: | ---: | ---: | ---: | ---: |
| off | 18.00 / 1.54 | 15.01 / 6.26 | 17.44 / 6.31 | 18.25 / 2.25 | 3.77 / 0.49 |
| 1.2 | 14.09 / 4.72 | 12.49 / 7.61 | 14.72 / 7.28 | 14.12 / 5.00 | 2.82 / 1.09 |
| 1.5 | 9.18 / 9.97 | 9.31 / 10.91 | 10.94 / 13.32 | 9.63 / 9.77 | 1.70 / 2.19 |
| 1.8 | 5.48 / 14.21 | 8.13 / 13.59 | 9.97 / 16.84 | 5.69 / 14.10 | 1.06 / 3.12 |
| sRGB | 3.81 / 18.87 | 9.06 / 17.02 | 11.26 / 19.51 | 4.12 / 19.49 | 0.90 / 3.83 |

**What Floyd–Steinberg's picture gives off** (the original: 37.8% of white's light, mean stored value 135.5):

| Gamma | Light, % of white | Mean stored value |
| :--- | ---: | ---: |
| off | 53.2 | 135.5 |
| 1.2 | 49.5 | 126.3 |
| 1.5 | 45.2 | 115.2 |
| 1.8 | 41.7 | 106.4 |
| sRGB | 37.9 | 96.7 |

**The color composite, 4 levels per channel** (512²; ΔE after blurring, RMS, as: whole picture / the sphere):

| Gamma | Floyd–Steinberg, in light | Floyd–Steinberg, stored | Atkinson, in light | Atkinson, stored |
| :--- | ---: | ---: | ---: | ---: |
| off | 5.01 / 7.05 | 1.17 / 1.24 | 5.86 / 7.99 | 3.95 / 3.44 |
| 1.2 | 3.89 / 5.44 | 1.91 / 2.61 | 5.12 / 6.37 | 4.17 / 3.93 |
| 1.5 | 2.51 / 3.31 | 3.37 / 5.02 | 4.51 / 4.88 | 4.81 / 5.38 |
| 1.8 | 1.75 / 2.12 | 4.67 / 7.10 | 4.28 / 4.15 | 5.55 / 6.99 |
| sRGB | 1.58 / 1.95 | 5.46 / 8.09 | 4.18 / 3.65 | 6.01 / 7.41 |

**The machine screens** (the test image at the screen's size; ΔE after blurring, RMS over the whole picture, as: viewed in light / viewed on stored values):

| Gamma | ZX Spectrum, Bayer 2 | ZX Spectrum, Bayer 4 | ZX Spectrum, Atkinson | C64, Bayer 2 | C64, Bayer 4 | C64, Atkinson |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| off | 22.67 / 13.93 | 23.42 / 11.92 | 21.12 / 13.34 | 22.30 / 19.83 | 22.69 / 19.40 | 20.62 / 19.40 |
| 1.2 | 20.53 / 14.47 | 20.81 / 12.57 | 18.78 / 14.80 | 22.03 / 20.21 | 22.02 / 19.52 | 20.09 / 19.80 |
| 1.5 | 19.08 / 16.64 | 17.85 / 16.01 | 16.75 / 17.53 | 21.50 / 20.88 | 21.55 / 20.49 | 19.69 / 20.59 |
| 1.8 | 18.96 / 19.67 | 16.32 / 19.20 | 16.08 / 20.36 | 21.38 / 21.86 | 21.40 / 21.58 | 19.56 / 21.46 |
| sRGB | 19.28 / 24.93 | 16.25 / 23.35 | 16.82 / 24.41 | 21.86 / 23.64 | 21.55 / 23.22 | 19.49 / 22.72 |

**What they show:**

- **The two views disagree, and the curve is the lever between them.**
  Black-and-white Floyd–Steinberg: seen in light, the error falls from
  18.0 (off) to 3.8 (sRGB); seen on stored values, it rises from 1.5 to
  18.9. Off gives off 53.2% of white's light where the original has 37.8%
  (at 1:1 the picture is too light), but its stored values average the
  original's 135.5 exactly. sRGB gives 37.9% of the light, but its stored
  values average 96.7: scaled by a smoothing viewer, it is too dark by 39
  steps. So "off" by default isn't arbitrary: it is exact for every view
  that averages stored values, most views of a picture on a page.
- **1.5 is the compromise.** For all five gray methods, and for both
  kernels at 4 levels in color, the larger of the two errors is smallest
  at 1.5: Floyd–Steinberg 10.0, against 18.0 off and 18.9 sRGB; Bayer 4
  9.8, against 18.3 and 19.5; color Floyd–Steinberg 3.4, against 5.0 and
  5.5. That agrees with the user's own view (2026-11-11), which behaved
  like a gamma between 1.0 and 1.5, where 1.5 looked closest. An input
  for revisiting the default later; not decided here.
- **Dark tones aren't in those errors.** A dark area turned black adds
  little to a root mean square. The table of flat grays and the pictures
  carry it: with Bayer 2 under sRGB every gray up to 99 comes out black,
  with Atkinson up to 65, and the sphere's shadow side and background
  vanish (`samples/linear-light/as-built/gray-sphere-grid.png`), although
  ΔE says 1.8 and sRGB improve the light view.
- **Machine screens: the errors are the two colors per cell's** (ΔE 16 to
  23 under any gamma). On the ZX Spectrum the light view improves by 16%
  (Bayer 2, at 1.8), 31% (Bayer 4, sRGB) and 24% (Atkinson, 1.8), while
  the stored view worsens by 79%, 96% and 83% at sRGB. On the C64 the
  light view improves by only 4% to 6%, and the stored view worsens by
  17% to 20%. With Bayer 2 under sRGB the ZX sphere's body goes black
  (`zx-grid.png`). **The recommendation stands:** `off` for machine
  screens (the look of the time, the dark tones exact, and the best when
  scaled), and `1.5` or `srgb` with Bayer 4 only as something to try for
  a picture seen at 1:1.
- **The web UI's preparing costs next to nothing under a curve:** the
  fit to 256 × 192 takes ×1.07 (46 → 49 ms) for 12.6 megapixels and ×1.06
  (170 → 181 ms) for 48, and flattening onto white ×1.18 (58 → 69 ms) and
  ×1.01 (223 → 225 ms); in Node, with the page's compiled code.

Montages of these pictures, labeled, for looking: `gray-sphere-grid.png`,
`color-sphere-grid.png`, `zx-grid.png`, `c64-grid.png` and
`gray-shadow-5x.png` in `samples/linear-light/as-built/`.

**The timings** are in `docs/benchmarks-dithering.md`, "2026-11-15 — What
a gamma costs": sRGB takes about a third longer at 1024² (×1.34 in the
median over the configurations): gray with a threshold ×1.2, levels per
channel about nothing, the web-safe palette ×1.4 to ×2.0 (its `off` runs
switch between two speeds), Bayer 8 ×1.5, a picture turned gray ×1.57 for
the whole process, and the ZX Spectrum's screen 0.1 to 0.2 s more.

## Plan

1. **Settle the open decisions** in this file.
2. **Library:** the five curves and their tables (decision 2), no
   conversion by default, the conversions, machine cells included, with
   the new exact checks as properties; the self-check and its stored
   digest, run in Node by the tests; the gray helper (decision 4).
3. **CLI:** `--gamma` with its five values, `off` by default, and the
   self-check's mode; the gray helper in place of its `luma`, and
   `--gray`'s help text (luma only with `off`). The logo's script,
   `logo/make-logo.mjs`, passes `--gamma off` in its CLI call, since it
   gives every setting, and its comment there, which still calls linear
   light the planned default, is updated; `npm run logo` must then
   report every file unchanged.

   **As built** (2026-11-14, agreed with the user):
   - `--gamma NAME`, `off` by default; the help shows "off (the
     default, also 1.0)", and `1` is accepted silently too. Any other
     value is rejected with the five names. It combines with every mode.
     `Main` always calls the `…With` drivers; the report line names the
     gamma only when it isn't `off` ("…, threshold 128.0, gamma srgb,
     gray"), so with `off` it stays as it was.
   - `--gray` and the gray pipeline use `toGray`; `toNeutral` takes the
     gamma; the CLI's `luma` is gone.
   - `--check-engine`, a mode of its own: optparse has two
     alternatives, so `parseOptions` returns `CheckEngine | Dither
     Options`, and the usage line shows both; with other arguments it's
     rejected. It prints "Engine check passed: …" and exits with 0, or
     "Engine check failed:" and the problems, with 1.
   - The logo's script passes `--gamma off`, and `logo/README.md` says
     so: `npm run logo` wrote nothing, 28 files unchanged.
   - `check:cli`, four new checks: 13, `--gamma off`, `1.0` and `1`
     byte-identical to no `--gamma` (gray, per channel, a ZX `.scr`);
     14, checks 1, 2, 4 and 6 under each curve, with two kernels where
     the error is zero; 15, exact dot counts with `srgb` and pure Bayer
     8 through each pipeline, a flat 128 at 14 in 64 in gray and per
     channel and 20 on a ZX screen (0.314 of the way to white 216 in
     light; 32 and 38 without a curve), which caught each of the three
     pipelines' gamma dropped in `Main` (the exact checks can't: an
     unchanged picture stays unchanged under any curve); 16,
     `--check-engine`. `check:cli` takes 70 s instead of 39.
4. **Web UI:** the same five values and default, the fit and the
   flattening in the curve's light (decision 6), and the self-check in a
   worker of its own, with a notice; the gray helper in place of its
   copies. In the same branch as the CLI:
   `check:web` compares the page with the CLI, so the two change
   together, and it runs the self-check in the three browsers.

   Split into three sub-steps (agreed 2026-11-15): 4a, the gamma through
   the dithering, with its control; 4b, the fit and the background in
   the curve's light, back to a byte by the converted half-steps,
   `toLight(b + 0.5)` (the nearest byte on stored values, as
   `nearestLevel`'s cuts; the user chose it over `fromLight` and
   rounding); 4c, the self-check, shown as an icon left of Help (gray
   while it runs, a green circle with ✓, a yellow triangle with !), with
   a short tooltip and the details in the README. The flattening stays in
   the web UI until the CLI's `--background` needs it (start closed).

   **As built, 4a** (2026-11-15):
   - `Settings` has `gamma`, sent to the worker by the CLI's names and
     checked there; "Gamma" segments in step 4, after the Bayer map and
     before "gray first": Off, 1.2, 1.5, 1.8, sRGB.
   - The worker dithers with `initDitheringWith` and `ditherBandsWith`;
     gray by `toGray`, so the web UI's copies of `luma` are gone.
   - The result's name and "Done:" say "gamma 1.5" or "gamma sRGB"; the
     download names `gamma1.2`, `gamma1.5`, `gamma1.8` and `srgb` (the
     user's choice), after the Bayer map; nothing for Off.
   - `RunSpec` adds 5 settings and 3 machine settings under curves
     against the CLI's path; dropping the gamma from each of the three
     paths was caught. `check:web`: 72 checks, 4 new per engine.
   - Follow-up (2026-11-15, after the user's manual test): a note under
     the gamma while it can't change the picture (`gammaActs`): without
     colors, or without a method, gray first and a picture mixed while
     it's prepared, each pixel takes the nearest color on stored values,
     which no curve changes. Two states that look alike in step 4, after
     loading and after a Bayer map chosen and set back to none (which
     keeps its 2 levels), both show it. The segments keep their order,
     Off to sRGB, a scale (the user agreed); a hint to try sRGB for
     photos goes into the README's settings (step 6).

   **As built, 4b** (2026-11-15):
   - With off, `Prepare.js`'s integer loops are unchanged. With a curve,
     `lightTables` gives each byte's light and each half-step's,
     `toLight(b + 0.5)`, by the library's public `toLight`; the
     flattening mixes `light[color] × a + light[background] × (1 − a)`,
     the fit sums each pixel's light by the same whole-number overlaps
     in the same order, and both go back to a byte by counting the
     half-steps at or below (`byteOfLight`). A gamma's change prepares
     the picture again.
   - `PrepareSpec`: every byte back from its light, a half-step going
     up; alpha 0 and 255 exact; the loops as the rules, for every value
     and alpha and for five fits, under every curve; decision 6's
     examples, lines halved to 188 (128 with off) and half-transparent
     black over white to 188 or 187. Mutations: the flattening ignoring
     light and the fit summing stored values were caught; the half-step
     rounded down at first wasn't (the whole pictures never hit a
     half-step exactly), so `byteOfLight` became the loops' own
     JavaScript function, whose tests then caught it.
   - `check:web` found that WebKit read semi-transparent colors off,
     before any curve and with off too: its `ImageBitmap` stays
     premultiplied. The page now reads such a picture as an `<img>`
     through WebGL, exact in all three engines, accepted only if it
     agrees with the canvas's exact bytes (web/CLAUDE.md,
     "Transparency"). `check:web`: 83 checks.

   **As built, 4c** (2026-11-15):
   - Once the page has its copy of `worker.js` in memory, a worker of
     its own runs the library's `checkEngine` (the request `{ kind:
     "check" }`; a job has no `kind`) and answers whether it passed,
     with the problems; the page then ends it. A worker that can't
     start, or fails, leaves the check "couldn't run", gray, not failed.
   - The icon left of Help (in the footer on a phone): a gray disc while
     it runs, a disc with a check mark in the accent when it passed, a
     triangle with ! in `--warn` when it failed, the C64's orange
     `#9f4815` in the light theme and the ZX Spectrum's yellow `#d8d800`
     in the dark (the mockups agreed with the user; contrast 6.2 and
     11.6). The marks are cut out of the shapes. A button with the state
     as its name opens a popup, as the list of formats opens: the
     sentence and "Details in Help", the README's new section "The
     engine check"; Escape and a click outside close it.
   - On a failure the alert region says the sentence once, and the
     console lists the problems. The page's root has
     `data-engine-check` for `check:web`, which expects `passed` in all
     three engines: 86 checks.
5. **Measure:** the benchmarks, a look at the test images, and the
   machine screens' recommendations again (the quality measurements are
   in [Measured, as built](#measured-as-built-step-5-2026-11-15)).
6. **Docs and release:** see below, then the release, 0.2.2 (decision
   1), and this file is deleted. The docs include how to write an
   efficient quantizer: with `quantizeLinear`, the coefficients converted
   in the outer `let`, once, not in the per-pixel function. In
   `quantizeLinear`'s doc comment, which Pursuit shows, and in the
   reference docs. They also show decision 1's two cases for authors: a
   quantizer whose values are kept as they are, and numbers made for one
   curve converted for another.

## Docs to update at the end

- `docs/gamma.md`, new (the user, 2026-11-12): what `--gamma` means (it
  doesn't adjust the picture), which value for which view, the table of
  dark tones lost, `off` with Atkinson and for machine screens; linked
  from the READMEs, and later from the web UI's (i);
- `README.md`, "You need the best photo quality";
- `cli/README.md` and `web/README.md`, their limitations and options
  (`cli/README.md`'s "fixing this is planned" becomes `--gamma`). The
  CLI's (step 3): `--gamma` (the help shows "off (the default, also
  1.0)"; `1` is accepted too), `--check-engine` (a mode, with its exit
  codes in the table), `--gray`'s meaning under a curve, and the
  report line, which names the gamma when it isn't `off` ("Output and
  timing" keeps its example);
- `docs/test-images.md`, "Exact checks": `check-cli.sh`'s checks 13 to
  16;
- `docs/ordered-dithering.md` (its formulas and exact properties),
  `docs/error-diffusion.md`, `docs/test-images.md`,
  `docs/machine-screens/README.md`;
- `TODO.md`: the item goes, with its "skews mid-tones slightly", and
  `web/ROADMAP.md`;
- `logo/README.md`, "How it's made": the CLI settings it lists gain
  `--gamma off`;
- `CHANGELOG.md`, `CLAUDE.md` (its logo entry asks for the opt-out; it
  then says the script passes `--gamma off`; its CLI entry gains
  `--gamma`, `--check-engine` and the `Command` type; its documentation map gets
  `docs/exact-arithmetic.md`, written in sub-step 2a, with the curves'
  and the self-check's sections added as they come).

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
