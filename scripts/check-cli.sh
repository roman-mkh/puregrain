#!/usr/bin/env bash
# End-to-end checks of the dither CLI against the exact properties of the
# test images (docs/test-images.md, "Exact checks"). Each check runs the
# real CLI on generated images; exits non-zero on the first failure.
# Build first (npm run build). Outputs go to samples/check/ (gitignored).
set -euo pipefail

root=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")/..
cd "$root"
out=samples/check
cli="node cli/bin/puregrain-cli.mjs"
mkdir -p $out

node scripts/generate-images.mjs --pattern color --out $out >/dev/null
node scripts/generate-images.mjs --pattern color:palette-exact --out $out >/dev/null
node scripts/generate-images.mjs --pattern color:channel-ramps --out $out >/dev/null

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; exit 1; }

# 1. vectorED with the web-safe palette == scalarED with 6 levels per
#    channel (the cube's steps), byte for byte — proved as a property in
#    Test.Dither.PaletteSpec, checked here through the whole CLI.
$cli $out/color-512.png $out/websafe.png --palette websafe216 >/dev/null
$cli $out/color-512.png $out/levels6.png --levels 6 >/dev/null
cmp -s $out/websafe.png $out/levels6.png \
  && pass "color composite: --palette websafe216 == --levels 6 (byte-identical)" \
  || fail "color composite: --palette websafe216 != --levels 6"

# 2. An image made only of palette colors has zero error everywhere, so it
#    must come back unchanged — in both modes.
for mode in "--palette websafe216" "--levels 6"; do
  $cli $out/color-palette-exact-512.png $out/exact.png $mode >/dev/null
  cmp -s $out/color-palette-exact-512.png $out/exact.png \
    && pass "color:palette-exact alone, $mode: output == input" \
    || fail "color:palette-exact alone, $mode: output differs from input"
done

# 3. The gray stripe is the top quarter of color:channel-ramps. Rendered
#    alone, all three channels start with zero error and identical input,
#    so every pixel there must stay exactly neutral (r = g = b).
for mode in "--levels 4" "--palette websafe216"; do
  $cli $out/color-channel-ramps-512.png $out/ramps.png $mode >/dev/null
  colored=$(node -e '
    const fs = require("fs"); const { PNG } = require("pngjs");
    const p = PNG.sync.read(fs.readFileSync(process.argv[1]));
    let n = 0;
    for (let y = 0; y < p.height / 4; y++) for (let x = 0; x < p.width; x++) {
      const i = (y * p.width + x) * 4;
      if (p.data[i] !== p.data[i + 1] || p.data[i + 1] !== p.data[i + 2]) n++;
    }
    console.log(n);' $out/ramps.png)
  [ "$colored" -eq 0 ] \
    && pass "color:channel-ramps alone, $mode: gray stripe exactly neutral" \
    || fail "color:channel-ramps alone, $mode: $colored non-neutral pixels in the gray stripe"
done

# 4. Ordered dithering without diffusion passes no error between pixels,
#    and hands all three channels of a pixel the same value and the same
#    position: every neutral pixel of the whole color composite must stay
#    neutral (with error diffusion this only holds for a tile on its own).
$cli $out/color-512.png $out/bayer-none.png --bayer 4 --kernel none --levels 4 >/dev/null
counts=$(node -e '
  const fs = require("fs"); const { PNG } = require("pngjs");
  const a = PNG.sync.read(fs.readFileSync(process.argv[1]));
  const b = PNG.sync.read(fs.readFileSync(process.argv[2]));
  let neutral = 0, colored = 0;
  for (let i = 0; i < a.data.length; i += 4) {
    if (a.data[i] === a.data[i + 1] && a.data[i + 1] === a.data[i + 2]) {
      neutral++;
      if (b.data[i] !== b.data[i + 1] || b.data[i + 1] !== b.data[i + 2]) colored++;
    }
  }
  console.log(neutral + " " + colored);' $out/color-512.png $out/bayer-none.png)
set -- $counts
[ "$1" -gt 0 ] && [ "$2" -eq 0 ] \
  && pass "color composite, --bayer 4 --kernel none --levels 4: all $1 neutral pixels stay neutral" \
  || fail "color composite, --bayer 4 --kernel none --levels 4: $2 of $1 neutral pixels came out colored"

# 5. Ordered dithering keeps a value that is exactly a level, so an image
#    made only of web-safe colors (6 levels per channel) comes back
#    unchanged: without diffusion, and in the hybrid, where the error is
#    zero everywhere too.
for kernel in none floyd-steinberg; do
  $cli $out/color-palette-exact-512.png $out/exact-bayer.png --levels 6 --bayer 4 --kernel $kernel >/dev/null
  cmp -s $out/color-palette-exact-512.png $out/exact-bayer.png \
    && pass "color:palette-exact alone, --levels 6 --bayer 4 --kernel $kernel: output == input" \
    || fail "color:palette-exact alone, --levels 6 --bayer 4 --kernel $kernel: output differs from input"
done
