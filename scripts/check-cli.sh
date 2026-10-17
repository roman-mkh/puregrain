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
node scripts/generate-images.mjs --pattern color:zx-cells --size 256x192 --out $out >/dev/null
node scripts/generate-images.mjs --pattern color:c64-cells --size 320x200 --out $out >/dev/null
node scripts/generate-images.mjs --pattern color --size 256x192 --out $out >/dev/null
node scripts/generate-images.mjs --pattern color --size 320x200 --out $out >/dev/null

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; exit 1; }

# 1. vectorED with the web-safe palette == scalarED with 6 levels per
#    channel (the cube's steps), byte for byte — proved as a property in
#    Test.Puregrain.PaletteSpec, checked here through the whole CLI.
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

# 6. An image made only of valid cells of a machine's screen (each 8×8
#    cell only the two colors of one of its cells: a ZX Spectrum
#    attribute's ink and paper, or a C64 hires cell's two colors) fits the
#    machine's own cells exactly, so the error is zero everywhere and it
#    must come back unchanged: with error diffusion and without, and with
#    ordered dithering inside the cells, pure and combined with a kernel
#    (every threshold lies strictly between a cell's two colors). The CLI
#    twin of the properties in Test.Puregrain.ZxSpectrumSpec and
#    Test.Puregrain.C64Spec.
for screen in "zx-spectrum zx-cells 256x192" "c64-hires c64-cells 320x200"; do
  set -- $screen
  for mode in "--kernel floyd-steinberg" "--kernel none" "--bayer 8" "--bayer 8 --kernel floyd-steinberg"; do
    $cli $out/color-$2-$3.png $out/$1.png --machine $1 $mode >/dev/null
    cmp -s $out/color-$2-$3.png $out/$1.png \
      && pass "color:$2 alone, --machine $1 $mode: output == input" \
      || fail "color:$2 alone, --machine $1 $mode: output differs from input"
  done
done

# 7. A .scr file (--format scr) holds the same picture as the PNG of the
#    same run. It's decoded here independently: each pixel's byte by the
#    Spectrum's address formula, its bit (1 = ink), its cell's attribute,
#    and the colors from the code bits (0xD8 normal, 0xFF bright). It must
#    match the PNG pixel for pixel, be 6912 bytes long, and leave FLASH off.
$cli $out/color-256x192.png $out/zx-color.png --machine zx-spectrum --kernel atkinson >/dev/null
$cli $out/color-256x192.png $out/zx-color.scr --machine zx-spectrum --kernel atkinson --format scr >/dev/null
result=$(node -e '
  const fs = require("fs"); const { PNG } = require("pngjs");
  const scr = fs.readFileSync(process.argv[1]);
  const png = PNG.sync.read(fs.readFileSync(process.argv[2]));
  if (scr.length !== 6912) { console.log(scr.length + " bytes, not 6912"); process.exit(); }
  let wrong = 0, flash = 0;
  for (let i = 6144; i < 6912; i++) if (scr[i] & 128) flash++;
  for (let y = 0; y < 192; y++) for (let x = 0; x < 256; x++) {
    const address = ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3);
    const isInk = (scr[address] >> (7 - (x & 7))) & 1;
    const attribute = scr[6144 + (y >> 3) * 32 + (x >> 3)];
    const code = isInk ? attribute & 7 : (attribute >> 3) & 7;
    const level = attribute & 64 ? 255 : 216;
    const i = (y * 256 + x) * 4;
    if (png.data[i] !== (code & 2 ? level : 0) || png.data[i + 1] !== (code & 4 ? level : 0)
      || png.data[i + 2] !== (code & 1 ? level : 0)) wrong++;
  }
  console.log(wrong === 0 && flash === 0 ? "ok" : wrong + " pixels differ, " + flash + " cells with FLASH");' \
  $out/zx-color.scr $out/zx-color.png)
[ "$result" = ok ] \
  && pass "color composite at 256x192, --machine zx-spectrum --format scr: the .scr decodes to the PNG" \
  || fail "color composite at 256x192, --machine zx-spectrum --format scr: $result"

# 8. A .scr file, a tape, a .prg or an .art holds exactly one screen
#    (256×192, or 320×200 for the C64), so another size is rejected before dithering:
#    exit code 1, an error naming the size, and no file written.
for target in "zx-spectrum scr 256x192" "zx-spectrum tap 256x192" "c64-hires prg 320x200" "c64-hires art 320x200"; do
  set -- $target
  rm -f $out/wrong-size.$2
  code=0
  $cli $out/color-512.png $out/wrong-size.$2 --machine $1 --format $2 >/dev/null 2>$out/wrong-size.err || code=$?
  [ "$code" -eq 1 ] && [ ! -e $out/wrong-size.$2 ] && grep -q "needs a $3 image" $out/wrong-size.err \
    && pass "color composite at 512x512, --machine $1 --format $2: rejected (exit 1), no file written" \
    || fail "color composite at 512x512, --machine $1 --format $2: exit code $code (expected 1), file written: $([ -e $out/wrong-size.$2 ] && echo yes || echo no), error: $(cat $out/wrong-size.err)"
done

# 9. A tape (.tap; the format comes from the extension here, without
#    --format, so the CLI's inference is checked too) holds a BASIC loader,
#    then the screen: read here
#    independently, block by block (two-byte length, low byte first; flag;
#    bytes; checksum, so that all of a block's bytes XOR to 0). Program
#    header (type 0, autostart line 10, its length), the loader's bytes
#    (10 LOAD "" SCREEN$: PAUSE 0, as the Spectrum stores it), screen
#    header (type 3, 6912 bytes at 16384), both named after the output
#    file, and the screen's bytes equal to the .scr of the same run (7).
$cli $out/color-256x192.png $out/zx-color.tap --machine zx-spectrum --kernel atkinson >/dev/null
result=$(node -e '
  const fs = require("fs");
  const tap = fs.readFileSync(process.argv[1]);
  const scr = fs.readFileSync(process.argv[2]);
  const blocks = [];
  let at = 0, problem = "";
  while (at < tap.length && !problem) {
    const n = tap[at] | (tap[at + 1] << 8);
    const body = tap.subarray(at + 2, at + 2 + n);
    if (n < 2 || body.length !== n) problem = "the block at " + at + " is cut short";
    else if (body.reduce((x, b) => x ^ b, 0) !== 0) problem = "the block at " + at + " has a wrong checksum";
    else blocks.push({ flag: body[0], bytes: body.subarray(1, n - 1) });
    at += 2 + n;
  }
  const word = (b, i) => b[i] | (b[i + 1] << 8);
  const name = (b) => String.fromCharCode(...b.subarray(1, 11));
  const loader = [0, 10, 14, 0, 0xef, 0x22, 0x22, 0xaa, 0x3a, 0xf2, 0x30, 0x0e, 0, 0, 0, 0, 0, 0x0d];
  if (!problem) {
    const [ph, pd, sh, sd] = blocks;
    if (blocks.map((b) => b.flag).join() !== "0,255,0,255") problem = "flags " + blocks.map((b) => b.flag).join();
    else if (ph.bytes[0] !== 0 || word(ph.bytes, 13) !== 10 || word(ph.bytes, 11) !== pd.bytes.length
      || word(ph.bytes, 15) !== pd.bytes.length) problem = "the program header";
    else if (Buffer.compare(Buffer.from(loader), pd.bytes) !== 0) problem = "the loader: " + [...pd.bytes].join();
    else if (sh.bytes[0] !== 3 || word(sh.bytes, 11) !== 6912 || word(sh.bytes, 13) !== 16384) problem = "the screen header";
    else if (name(ph.bytes) !== "zx-color  " || name(sh.bytes) !== "zx-color  ") problem = "the names";
    else if (Buffer.compare(sd.bytes, scr) !== 0) problem = "the screen differs from the .scr";
  }
  console.log(problem || "ok");' $out/zx-color.tap $out/zx-color.scr)
[ "$result" = ok ] \
  && pass "color composite at 256x192, --machine zx-spectrum to a .tap: loader, then the .scr's screen" \
  || fail "color composite at 256x192, --machine zx-spectrum to a .tap: $result"

# 10. --machine-palette picks which of the Spectrum's colors the cells may
#     use: with normal, every channel of every pixel is 0 or 216 (0xD8);
#     with bright, 0 or 255 (black is the same either way).
for palette in "normal 216" "bright 255"; do
  set -- $palette
  $cli $out/color-256x192.png $out/zx-$1.png --machine zx-spectrum --machine-palette $1 --bayer 8 >/dev/null
  others=$(node -e '
    const fs = require("fs"); const { PNG } = require("pngjs");
    const p = PNG.sync.read(fs.readFileSync(process.argv[1])); const level = Number(process.argv[2]);
    let n = 0;
    for (let i = 0; i < p.data.length; i += 4) for (let c = 0; c < 3; c++) if (p.data[i + c] !== 0 && p.data[i + c] !== level) n++;
    console.log(n);' $out/zx-$1.png $2)
  [ "$others" -eq 0 ] \
    && pass "color composite at 256x192, --machine zx-spectrum --machine-palette $1: every channel 0 or $2" \
    || fail "color composite at 256x192, --machine zx-spectrum --machine-palette $1: $others channel values other than 0 and $2"
done

# 11. A .prg (the format from the extension) is a C64 program that shows
#     the picture of the PNG of the same run. It's read here
#     independently: the load address, 2049; the BASIC viewer, line by
#     line through each line's link, with the keywords' tokens written out
#     here, against its listing; the colors at 3072 (foreground × 16 +
#     background) and the bitmap at 8192 (each cell's 8 bytes in a row, 1
#     for the foreground), with Colodore's values written out here. It
#     must match the PNG pixel for pixel and be 14,145 bytes long.
$cli $out/color-320x200.png $out/c64-color.png --machine c64-hires --bayer 8 >/dev/null
$cli $out/color-320x200.png $out/c64-color.prg --machine c64-hires --bayer 8 >/dev/null
result=$(node -e '
  const fs = require("fs"); const { PNG } = require("pngjs");
  const prg = fs.readFileSync(process.argv[1]);
  const png = PNG.sync.read(fs.readFileSync(process.argv[2]));
  const at = (address) => prg[address - 2049 + 2] ?? 0;
  const problems = [];
  if (prg.length !== 14145) problems.push(prg.length + " bytes, not 14145");
  if (prg[0] + 256 * prg[1] !== 2049) problems.push("loads at " + (prg[0] + 256 * prg[1]) + ", not 2049");
  const tokens = { 0xC2: "PEEK", 0x97: "POKE", 0xAF: "AND", 0xB0: "OR", 0xA1: "GET", 0x8B: "IF", 0xA7: "THEN", 0xB2: "=" };
  const lines = [];
  for (let address = 2049; at(address) + at(address + 1) > 0 && lines.length < 100; ) {
    let end = address + 4;
    while (at(end) !== 0) end++;
    const link = at(address) + 256 * at(address + 1);
    if (link !== end + 1) { problems.push("a line links to " + link + ", not " + (end + 1)); break; }
    let text = "", plain = "";
    for (let a = address + 4; a < end; a++) {
      text += tokens[at(a)] ?? (at(a) < 128 ? String.fromCharCode(at(a)) : "{" + at(a) + "}");
      plain += tokens[at(a)] ? "_" : String.fromCharCode(at(a));
    }
    if (Object.values(tokens).some((k) => plain.includes(k))) problems.push("a keyword stored as letters: " + plain);
    lines.push((at(address + 2) + 256 * at(address + 3)) + " " + text);
    address = link;
  }
  const expected = [
    "10 B=PEEK(53280):D=PEEK(53265):M=PEEK(53272)",
    "20 POKE 53265,D AND 239:POKE 53280,0:POKE 53272,56:POKE 53265,D OR 32",
    "30 POKE 198,0",
    "40 GET K$:IF K$=\"\" THEN 40",
    "50 POKE 53265,D AND 239:POKE 53272,M:POKE 53280,B:POKE 53265,D",
  ];
  if (lines.join("\n") !== expected.join("\n")) problems.push("the viewer lists as: " + lines.join(" / "));
  const colors = [0x000000, 0xffffff, 0x96282e, 0x5bd6ce, 0x9f2dad, 0x41b936, 0x2724c4, 0xeff347,
    0x9f4815, 0x5e3500, 0xda5f66, 0x474747, 0x787878, 0x91ff84, 0x6864ff, 0xaeaeae];
  let wrong = 0;
  for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
    const bit = (at(8192 + (y >> 3) * 320 + (x >> 3) * 8 + (y & 7)) >> (7 - (x & 7))) & 1;
    const c = at(3072 + (y >> 3) * 40 + (x >> 3));
    const rgb = colors[bit ? c >> 4 : c & 15];
    const i = (y * 320 + x) * 4;
    if (png.data[i] !== rgb >> 16 || png.data[i + 1] !== ((rgb >> 8) & 255) || png.data[i + 2] !== (rgb & 255)) wrong++;
  }
  if (wrong > 0) problems.push(wrong + " pixels differ");
  console.log(problems.length > 0 ? problems.join("; ") : "ok");' \
  $out/c64-color.prg $out/c64-color.png)
[ "$result" = ok ] \
  && pass "color composite at 320x200, --machine c64-hires to a .prg: the viewer, then the PNG's picture" \
  || fail "color composite at 320x200, --machine c64-hires to a .prg: $result"

# 12. An Art Studio file (.art) of the same picture, read here as RECOIL,
#     the library behind many C64 picture viewers, reads one (its
#     DecodeC64HiresFrame): the bitmap from offset 2, the colors from
#     offset 8002, a 0 bit the lower half of the cell's color byte and a 1
#     bit the upper, with Colodore's values written out here. It must match
#     the PNG of check 11's run pixel for pixel, be 9009 bytes long, load
#     at 8192, and hold the same bitmap and colors as that run's .prg.
$cli $out/color-320x200.png $out/c64-color.art --machine c64-hires --bayer 8 >/dev/null
result=$(node -e '
  const fs = require("fs"); const { PNG } = require("pngjs");
  const art = fs.readFileSync(process.argv[1]);
  const prg = fs.readFileSync(process.argv[2]);
  const png = PNG.sync.read(fs.readFileSync(process.argv[3]));
  const problems = [];
  if (art.length !== 9009) problems.push(art.length + " bytes, not 9009");
  if (art[0] + 256 * art[1] !== 8192) problems.push("loads at " + (art[0] + 256 * art[1]) + ", not 8192");
  const colors = [0x000000, 0xffffff, 0x96282e, 0x5bd6ce, 0x9f2dad, 0x41b936, 0x2724c4, 0xeff347,
    0x9f4815, 0x5e3500, 0xda5f66, 0x474747, 0x787878, 0x91ff84, 0x6864ff, 0xaeaeae];
  let wrong = 0;
  for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
    const offset = (y & ~7) * 40 + (x & ~7) + (y & 7);
    const bit = (art[2 + offset] >> (~x & 7)) & 1;
    const v = art[8002 + (offset >> 3)];
    const rgb = colors[bit === 0 ? v & 15 : v >> 4];
    const i = (y * 320 + x) * 4;
    if (png.data[i] !== rgb >> 16 || png.data[i + 1] !== ((rgb >> 8) & 255) || png.data[i + 2] !== (rgb & 255)) wrong++;
  }
  if (wrong > 0) problems.push(wrong + " pixels differ");
  const prgAt = (address) => prg[address - 2049 + 2];
  for (let o = 0; o < 8000; o++) if (art[2 + o] !== prgAt(8192 + o)) { problems.push("its bitmap differs from the .prg, at offset " + o); break; }
  for (let o = 0; o < 1000; o++) if (art[8002 + o] !== prgAt(3072 + o)) { problems.push("its colors differ from the .prg, at offset " + o); break; }
  console.log(problems.length > 0 ? problems.join("; ") : "ok");' \
  $out/c64-color.art $out/c64-color.prg $out/c64-color.png)
[ "$result" = ok ] \
  && pass "color composite at 320x200, --machine c64-hires to an .art: read as RECOIL does, the PNG's picture" \
  || fail "color composite at 320x200, --machine c64-hires to an .art: $result"
