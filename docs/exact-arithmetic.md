# Exact arithmetic: roots of our own

puregrain gives the same bytes from its library, its command-line tool and
its web app, puregrain lab, whatever JavaScript engine runs them. Converting values to
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

It isn't only theory. Firefox sent `Math.pow` through each platform's
math library, and `Math.pow(Math.PI, -100)` came out one unit in the last
place off on older Android phones; the fix was for Android, and the bug
notes that "Windows also has a less precise `std::pow`" (Bugzilla 2037094,
also 1775254). V8 has given `Math.pow(99, 99)` and `99 ** 99` different
results, in older reports.

## What else exists

Looked at on 2026-11-08, before writing roots of our own:

- **`@stdlib/math-base-special-pow`** (npm, Apache-2.0), a JavaScript port
  of FreeBSD's `pow` from Sun's fdlibm: its source uses only exact
  arithmetic, bit operations and `sqrt`, so it gives the same result on
  every engine, within one unit in the last place. But the library can't
  depend on an npm package: it ships no JavaScript of its own, and its
  dependencies are registry packages.
- **`decimal.js`**, wrapped by PureScript's `decimals`: the same
  everywhere, but slow decimal objects, and an npm package for its users
  to install.
- **CRlibm and CORE-MATH:** correctly rounded, so the same everywhere, but
  C libraries, with no JavaScript build found.
- **PureScript's packages** (the package set 81.11.4): `numbers`' `pow` is
  `Math.pow`; `precise`, `rationals`, `fixed-precision` and `bigints`
  compute exactly, but none offers a power such as x^2.4, as far as their
  names and descriptions say.

What the curves need is *the same* result everywhere, not the most
accurate one, and any computation made only of exact operations gives
that. sRGB's exponent is 2.4 = 12/5, so no general `pow` is needed: x^2.4
= x² × x^(2/5), from square and fifth roots.

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

## The engine self-check

The standard requires every engine to compute the curves' operations
alike, but an engine can have a fault, and an optimizing compiler can
break the rules, for example by fusing a multiplication and an addition
into one step, which the standard forbids. `Puregrain.SelfCheck` checks
the engine at hand: `checkEngine` runs the curves and compares the
results with a stored reference.

- **What it computes:** each of the four computed curves, both ways, for
  the bytes and the halves between them, the levels of 2 to 16 with their
  midpoints, sRGB's two switch points, a fractional threshold (96.5),
  values just outside 0–255, and 200,000 values from Park and Miller's
  "minimal standard" generator (next = 48271 × x mod (2³¹ − 1), with a
  fixed seed), scaled to [−20, 300]. That many, so that the engines'
  optimizing compilers, where such faults would show, run too.
- **The digests:** each result is taken apart exactly (its sign, its
  power of 2, and its 53-bit mantissa as two whole numbers, by halving,
  doubling and splitting, which lose nothing) and folded into a whole
  number: h becomes (h × 48271 + part) mod (2³¹ − 1), exact in a
  JavaScript number since every value stays below 2⁵³. Never the printed
  digits, whose last place the standard leaves open. One digest per curve
  and direction: eight.
- **The reference:** the eight digests as Node 22.14 computed them,
  confirmed identical on 2026-11-14 in Node 26.13, Chromium 156, Firefox
  157 and WebKit 27.2. They change only when a curve changes on purpose,
  in the same commit and with a CHANGELOG line, since pictures dithered
  with that curve change too; never just to make a check pass.
- **A check without a reference:** under every curve, every byte must
  come back exactly from its light, through the table.
- **The report:** `exactArithmetic` says whether everything passed, and
  `problems` gives a sentence for each failure, naming the curve and
  direction ("gammaSrgb, back: the results differ from the reference") or
  the byte.
- **Time:** about 0.45 s in Node 22, 0.43 to 0.61 s in the browsers. It
  runs only when called: the command-line tool has a mode for it,
  `--check-engine`, and puregrain lab a worker of its own, apart from
  the dithering.
- **A pass** means that this engine computed the reference values
  exactly: strong evidence, not proof for every value, so the docs say
  "checked", not "guaranteed".

The tests (`test/Test/Puregrain/SelfCheckSpec.purs`) run it in Node, and
check that a wrong digest is reported with its curve and direction. A
deliberate change of one curve's operation order, which moved some
results by their last bit, failed the self-check and nothing else: the
other tests compare with a tolerance, the digest compares bits.

## Sources

- [ECMA-262](https://tc39.es/ecma262/), the Math object: `Math.sqrt`
  ("Return 𝔽(the square root of ℝ(n))"), `Math.cbrt` ("an
  implementation-approximated Number value") and `Math.pow` (which returns
  `Number::exponentiate`, implementation-approximated too).
- Mozilla's Bugzilla, bugs 2037094 and 1775254: `Math.pow` through the
  platform's math library.
- The measurements: scratch scripts, not kept in the repository
  (2026-11-08 and 2026-11-14).
