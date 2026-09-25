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
