# Exact arithmetic: roots of our own

puregrain gives the same bytes from its library, its command-line tool and
its web app, whatever JavaScript engine runs them. Converting values to
light, for `--gamma`, needs powers such as x^2.4, and so roots. JavaScript's
own functions for those may give different results on different engines,
so puregrain computes its roots itself, from operations that every engine
must compute alike. This page explains why, how, and the one compromise
that comes with it.

## Why not `Math.pow` or `Math.cbrt`

ECMA-262, the standard that defines JavaScript, treats them differently
from the basic operations:

- **+, −, ×, ÷ and `Math.sqrt` are exact:** each must return the number
  nearest to the true result. For `Math.sqrt` the standard says "Return
  𝔽(the square root of ℝ(n))". Every correct engine gives the same bits.
- **`Math.pow` and `Math.cbrt` are approximated:** `Math.cbrt` returns "an
  implementation-approximated Number value representing the cube root", and
  `Math.pow` returns `Number::exponentiate`, approximated the same way. Each
  engine may use its own approximation.

Measured on 2026-11-08: Node 22's `Math.pow` and the browsers' (Chromium,
Firefox, WebKit) differ on about 10% of the values tried. For byte 18's
light, one gives 1.542452420828549 and the other 1.5424524208285488.

A difference in the last digit matters, because error diffusion amplifies
it: one pixel that flips passes a different error on, and the pattern after
it changes. The command-line tool saw it once in its gray conversion: values
one step off in the last digit changed 96% of a flat gray picture's pixels,
with the same average.

## How the roots are computed

`Puregrain.Internal.Exact` has the fifth root and the cube root; the square
root is JavaScript's own, which the standard defines exactly. Each root
takes four steps:

1. **Special values:** 0, the infinities and NaN come back as they are. A
   negative number is mirrored: its root is the negative of its
   magnitude's root.
2. **Range reduction:** the number is divided or multiplied by 32 (for the
   fifth root) or by 8 (for the cube root) until it lies in [1/32, 1) or
   [1/8, 1), counting a factor of 2 for each step. Powers of 2 are exact,
   so this loses nothing, and the root of 32 × x is exactly twice the root
   of x.
3. **Newton's method,** starting from 1: each step improves the guess y
   to (4y + m/y⁴)/5 for the fifth root of m, or (2y + m/y²)/3 for the cube
   root. A fixed number of steps, 10 and 9, so the result is a fixed
   sequence of exact operations, the same on every engine.
4. **Back to the number's size:** the result is multiplied by the counted
   factor, exactly.

**The step counts** were measured on 2026-11-14 over 400,000 values of the
reduced range: at most 9 steps for the fifth root and 8 for the cube root
until the value settled, that is until further steps kept it or only hopped
between it and a neighbouring number. One step of margin was added. Thanks
to the range reduction, the same counts fit every input, from the smallest
number JavaScript has up to the largest.

**Measured accuracy,** counted exactly with whole numbers (BigInt) over a
million random numbers: the result is the nearest number to the true root
for 71% of them, one unit in the last place away for 29%, and, for the
fifth root only, two units away for 0.014%. Perfect powers come out
exactly: the fifth root of k⁵ is k for every k up to 1000, the cube root of
k³ for every k up to 100,000.

## What the tests check

`test/Test/Puregrain/ExactSpec.purs`, for both roots:

- the fixed steps have settled, over a grid of 20,000 reduced values and
  1,000 random ones;
- the accuracy (root⁵ or root³ against x, within 2 × 10⁻¹⁵ or 1.2 ×
  10⁻¹⁵ relatively), over random numbers of every size;
- perfect powers come out exactly;
- the root of 32 × x (or 8 × x) is exactly twice the root of x;
- the root of −x is minus the root of x;
- the roots rise, apart from the dips of neighbouring numbers described
  below, and numbers a millionth apart keep their order;
- 0, the infinities, NaN and the smallest numbers.

## Neighbouring numbers

Found on 2026-11-14, by the test that the roots rise.

**What happens.** A computer number has about 16 digits. The true root of
most numbers falls between two numbers the computer can store, like a
length between two marks on a ruler. Newton's steps often end up hopping
between two marks around it, sometimes two marks apart with one skipped,
and after a fixed number of steps the result is whichever mark the last
step reached. So two inputs that differ only in their last digit can end
on different marks, and the larger input can get the smaller root, by one
or two units in the last place: about 1 or 2 parts in 10¹⁶.

**How often.** Over a million random pairs of neighbouring numbers, the
larger got the smaller root for 2,543 pairs with the fifth root (0.25%;
512 of them by two units) and for 1 pair with the cube root (by two
units). Always taking the lower mark of a hop reduced the fifth root's
count tenfold, but not to none. Only correctly rounded roots would remove
it: an exact computation of the remainder, to choose the nearest mark.
That's more code and more to verify.

**Why it doesn't matter.**

- Dithering only compares values that are far apart: pixels, levels,
  thresholds and the midpoints between levels differ by at least half a
  byte.
- Each root is within two units of the nearest number, so numbers more
  than a few units apart always keep their order.
- Every engine still gets exactly the same result, which is the point of
  this page.

**Decided** (with the user, 2026-11-14): the roots stay as they are. The
tests allow a dip of up to two units in the last place between
neighbouring numbers, and the light curves' tests check that the bytes and
the halves between them keep their order strictly. The first prototype (2026-11-08)
had found no larger input giving a smaller result over a million sorted
values: random values almost never land next to each other, so it missed
this.

## The light curves

`Puregrain.Gamma` turns stored values into light and back, on the same
0–255 scale, for `--gamma`'s values. Each curve is built from the roots
above and the square root, in a fixed order of operations; x is a stored
value divided by 255, L a light value divided by 255:

| Curve | To light | Back |
|---|---|---|
| `gammaOff` | x, not computed | L, not computed |
| `gamma1p2` | x · ⁵√x | √L · ∛L |
| `gamma1p5` | x · √x | (∛L)² |
| `gamma1p8` | x · (⁵√x)⁴ | (∛(∛L))⁵ |
| `gammaSrgb` | x / 12.92 up to 0.04045, above it y² · (⁵√y)² with y = (x + 0.055) / 1.055 | 12.92 · L up to 0.0031308, above it 1.055 · √√L · √∛L − 0.055 |

- **Negative values are mirrored:** the curve of −v is minus the curve of
  v, as the W3C's sample code (CSS Color 4) extends sRGB's. Dithering
  pushes corrected values below 0 in dark areas.
- **A table per curve:** the light of the 256 bytes, built the first time
  a curve is used and shared by all channels. A byte gets its light from
  the table, any other value from the formula, with the same result.
- **What's written goes back through the table.** The light of a byte is
  one of the table's entries, so the way back finds that byte exactly (8
  comparisons); any other value goes through the formula. The formula
  alone isn't enough: measured on 2026-11-14, it brings back every byte
  after rounding, but exactly only 37 to 130 of the 256, depending on the
  curve; `gammaSrgb` brings 255 back as 254.99999999999997. Through the
  table, a palette's colors and a ramp's levels come back as they were.
- **Order:** for every curve, the bytes and the halves between them rise
  strictly, which is what the dithering's comparisons rely on.
- **Alpha** isn't light: the conversion touches only the color channels
  (`Puregrain.Pixel`'s `ColorChannels`).

The tests (`test/Test/Puregrain/GammaSpec.purs`) check each of these, and
that the formulas match a reference written with `Math.pow` within 10⁻¹²;
a deliberate breakage of the table lookup was caught by five of them.

## Built on these roots

The engine's self-check uses these roots and curves; its section comes
with it.

## Sources

- [ECMA-262](https://tc39.es/ecma262/), the Math object: `Math.sqrt`
  ("Return 𝔽(the square root of ℝ(n))"), `Math.cbrt` ("an
  implementation-approximated Number value") and `Math.pow` (which returns
  `Number::exponentiate`, implementation-approximated too).
- The measurements: scratch scripts, not kept in the repository
  (2026-11-08 and 2026-11-14).
