// The puregrain logo's source: draws its shapes, dithers them with the
// puregrain CLI, and writes the pictures in this folder. Not under the
// MIT License: this script and the logo are under the terms in
// LICENSE.md, next to it.
//
// What the files are for, and how the logo is made: README.md, next to it.
// Run after npm run build: npm run logo. A picture is written only when
// its pixels changed, so that git status shows only real changes (zlib may
// compress the same pixels to other bytes on another version of Node).

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const cli = path.join(here, '..', 'cli', 'bin', 'puregrain-cli.mjs');

// The two color sets, equal (which suits which background: README.md):
// the ZX Spectrum's red and green (at normal brightness, 0xD8) with the
// 4 × 4 Bayer map, and the C64's orange and blue (Colodore's values,
// puregrain's c64 palette) with the 8 × 8 map. A gradient's dark dots
// take the first color, its light ones the second.
const sets = [
  { dir: 'zx', first: [0xd8, 0x00, 0x00], second: [0x00, 0xd8, 0x00], bayer: 4 },
  { dir: 'c64', first: [0x9f, 0x48, 0x15], second: [0x27, 0x24, 0xc4], bayer: 8 },
];

// ---- The shapes ----------------------------------------------------------

// A shape: its size in pixels, and for each pixel the part it belongs to,
// 0 for none: the mark's P is part 1 and its g part 2, every other shape
// is part 1.
const blank = (w, h) => ({ w, h, part: new Uint8Array(w * h) });

// The pixel font: 5 × 9 cells, lowercase, with descenders.
const font = {
  p: ['.....', '.....', '####.', '#...#', '#...#', '#...#', '####.', '#....', '#....'],
  u: ['.....', '.....', '#...#', '#...#', '#...#', '#..##', '.##.#', '.....', '.....'],
  r: ['.....', '.....', '#.##.', '##..#', '#....', '#....', '#....', '.....', '.....'],
  e: ['.....', '.....', '.###.', '#...#', '#####', '#....', '.###.', '.....', '.....'],
  g: ['.....', '.....', '.####', '#...#', '#...#', '.####', '....#', '#...#', '.###.'],
  a: ['.....', '.....', '.###.', '....#', '.####', '#...#', '.####', '.....', '.....'],
  i: ['.....', '..#..', '.....', '.##..', '..#..', '..#..', '.###.', '.....', '.....'],
  n: ['.....', '.....', '#.##.', '##..#', '#...#', '#...#', '#...#', '.....', '.....'],
};
// The mark's capital P, 5 × 7 cells.
const capitalP = ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'];

// Puts a glyph's cells ('#') into a shape as part `id`: from the cell
// (cx, cy) on, `cell` pixels to a cell, after a margin of `pad` pixels.
const put = (shape, rows, cx, cy, cell, pad, id) =>
  rows.forEach((row, ry) => [...row].forEach((c, rx) => {
    if (c !== '#') return;
    for (let y = 0; y < cell; y++) for (let x = 0; x < cell; x++) {
      shape.part[(pad + (cy + ry) * cell + y) * shape.w + pad + (cx + rx) * cell + x] = id;
    }
  }));

// The mark, "Pg" on a grid of 10 × 10 cells: the capital P from the
// second column, and the font's g, without its two empty rows, from the
// fifth column and the fourth row, so that the bottom bar of the P's head
// runs into the g's top bar: the shared corner.
const mark = (cell, pad) => {
  const n = 10 * cell + 2 * pad, shape = blank(n, n);
  put(shape, capitalP, 1, 0, cell, pad, 1);
  put(shape, font.g.slice(2), 4, 3, cell, pad, 2);
  return shape;
};

// The wordmark: "puregrain" in the font, an empty column between letters.
const wordmark = (cell, pad) => {
  const word = 'puregrain';
  const shape = blank((word.length * 6 - 1) * cell + 2 * pad, 9 * cell + 2 * pad);
  [...word].forEach((c, k) => put(shape, font[c], k * 6, 0, cell, pad, 1));
  return shape;
};

// The swash, "Pg" once more: the P's stem sweeps round under the g into
// the g's own stem, a tail shared by both. Drawn as areas of the square
// [-1, 1]² (y down), each a test of a point.
const ring = (cx, cy, inner, outer) => (u, v) => {
  const r = Math.hypot(u - cx, v - cy);
  return r >= inner && r <= outer;
};
const box = (x0, x1, y0, y1) => (u, v) => u >= x0 && u <= x1 && v >= y0 && v <= y1;
const any = (...areas) => (u, v) => areas.some((a) => a(u, v));
const both = (a, b) => (u, v) => a(u, v) && b(u, v);
const swashArea = any(
  box(-0.86, -0.60, -0.92, 0.22), // the P's stem
  both(ring(-0.47, -0.53, 0.14, 0.40), (u) => u > -0.6), // the P's bowl
  box(-0.86, -0.47, -0.92, -0.66), // the bowl's top bar
  box(-0.86, -0.47, -0.40, -0.13), // the bowl's bottom bar
  ring(0.30, -0.12, 0.13, 0.33), // the g's bowl
  box(0.42, 0.66, -0.40, 0.22), // the g's stem
  both(ring(-0.10, 0.22, 0.52, 0.76), (u, v) => v > 0.22), // the tail, from stem to stem
);
// The swash on n × n pixels, after a margin of `pad`: a pixel belongs to
// it when at least half of its 4 × 4 samples do.
const swash = (n, pad) => {
  const shape = blank(n + 2 * pad, n + 2 * pad);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    let inside = 0;
    for (let sy = 0; sy < 4; sy++) for (let sx = 0; sx < 4; sx++) {
      if (swashArea(((x + (sx + 0.5) / 4) / n) * 2 - 1, ((y + (sy + 0.5) / 4) / n) * 2 - 1)) inside++;
    }
    if (inside >= 8) shape.part[(y + pad) * shape.w + x + pad] = 1;
  }
  return shape;
};

// The outline: every pixel outside the shape that touches it, diagonally
// too. It goes around the holes as well, so the logo stands on any
// background.
const outlineOf = ({ w, h, part }) => {
  const outline = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    if (part[y * w + x]) continue;
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
      const yy = y + dy, xx = x + dx;
      if (yy >= 0 && yy < h && xx >= 0 && xx < w && part[yy * w + xx]) outline[y * w + x] = 1;
    }
  }
  return outline;
};

// ---- The dots, from puregrain --------------------------------------------

// The gray gradient under a shape: over its whole box, from 20 to 235
// (0.08 to 0.92 of 255), along the diagonal from the top left to the
// bottom right, or across from left to right.
const gradient = (w, h, along) => {
  const png = new PNG({ width: w, height: h });
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const t = along === 'diagonal' ? (x / (w - 1) + y / (h - 1)) / 2 : x / (w - 1);
    const g = Math.round(255 * (0.08 + 0.84 * t));
    png.data.set([g, g, g, 255], (y * w + x) * 4);
  }
  return png;
};

// The gradient under a shape, dithered by puregrain's CLI to two levels
// with a Bayer map: for each pixel, 1 for a light dot, 0 for a dark one.
// Every setting is given, so that a change of the CLI's defaults doesn't
// change the logo. (Dithering in linear light, planned as the default:
// pass its opt-out here once the CLI has it.)
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'puregrain-logo-'));
process.on('exit', () => fs.rmSync(work, { recursive: true, force: true }));
let runs = 0;
const dither = ({ w, h }, along, bayer) => {
  const input = path.join(work, `${runs}-gray.png`), output = path.join(work, `${runs}-dots.png`);
  runs++;
  fs.writeFileSync(input, PNG.sync.write(gradient(w, h, along), { colorType: 0 }));
  try {
    execFileSync(process.execPath,
      [cli, input, output, '--levels', '2', '--bayer', String(bayer), '--kernel', 'none', '--gray'],
      { stdio: 'pipe' });
  } catch (err) {
    process.stderr.write(err.stderr?.length ? err.stderr : `${err.message}\n`);
    process.exit(1);
  }
  const dots = PNG.sync.read(fs.readFileSync(output));
  return Uint8Array.from({ length: w * h }, (_, i) => (dots.data[i * 4] >= 128 ? 1 : 0));
};

// ---- Pictures ------------------------------------------------------------

// A shape painted, as RGBA: with dots, each in its set's color; without,
// flat, the P in the first color and the g in the second. The outline
// black, transparent around.
const paint = (shape, set, dots) => {
  const outline = outlineOf(shape), png = new PNG({ width: shape.w, height: shape.h });
  for (let i = 0; i < shape.w * shape.h; i++) {
    const part = shape.part[i];
    // With dots, a light one takes the second color; flat, the g does.
    const second = dots ? dots[i] === 1 : part === 2;
    const color = part ? (second ? set.second : set.first) : outline[i] ? [0, 0, 0] : null;
    if (color) png.data.set([...color, 255], i * 4);
  }
  return png;
};

// Copies the opaque pixels of a picture into another, at (left, top).
const copyInto = (to, from, left, top) => {
  for (let y = 0; y < from.height; y++) for (let x = 0; x < from.width; x++) {
    const i = (y * from.width + x) * 4;
    if (from.data[i + 3]) from.data.copy(to.data, ((top + y) * to.width + left + x) * 4, i, i + 4);
  }
  return to;
};
// Two pictures side by side, aligned at the top, with a gap between.
const beside = (a, gap, b) => {
  const png = new PNG({ width: a.width + gap + b.width, height: Math.max(a.height, b.height) });
  return copyInto(copyInto(png, a, 0, 0), b, a.width + gap, 0);
};
// A picture centered on a new one of w × h (rounded down to the left and
// the top), on a background color, or transparent without one.
const centered = (picture, w, h, background) => {
  const png = new PNG({ width: w, height: h });
  if (background) for (let i = 0; i < w * h; i++) png.data.set([...background, 255], i * 4);
  return copyInto(png, picture, Math.floor((w - picture.width) / 2), Math.floor((h - picture.height) / 2));
};
// A picture scaled by a whole number: each pixel becomes k × k.
const scaled = (picture, k) => {
  const png = new PNG({ width: picture.width * k, height: picture.height * k });
  for (let y = 0; y < png.height; y++) for (let x = 0; x < png.width; x++) {
    const from = (Math.floor(y / k) * picture.width + Math.floor(x / k)) * 4;
    picture.data.copy(png.data, (y * png.width + x) * 4, from, from + 4);
  }
  return png;
};

// ---- Files ---------------------------------------------------------------

// An SVG of a picture: a path per color, with a rectangle for each run of
// that color along a row. crispEdges keeps the dots square at any size.
const svgOf = ({ width: w, height: h, data }) => {
  const paths = new Map();
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w;) {
      const i = (y * w + x) * 4;
      if (!data[i + 3]) { x++; continue; }
      let end = x + 1;
      while (end < w && data.readUInt32BE((y * w + end) * 4) === data.readUInt32BE(i)) end++;
      const color = `#${data.toString('hex', i, i + 3)}`;
      paths.set(color, `${paths.get(color) ?? ''}M${x} ${y}h${end - x}v1h-${end - x}z`);
      x = end;
    }
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges">`
    + '<title>puregrain</title>'
    + [...paths].map(([color, d]) => `<path fill="${color}" d="${d}"/>`).join('')
    + '</svg>\n';
};

// An ICO file of several sizes, each a 32-bit bitmap (BGRA, its rows from
// the bottom up) followed by its 1-bit mask, 1 where it's transparent, as
// Windows and the browsers read them.
const icoOf = (pictures) => {
  const head = Buffer.alloc(6 + 16 * pictures.length);
  head.writeUInt16LE(1, 2); // an icon
  head.writeUInt16LE(pictures.length, 4);
  let offset = head.length;
  const bitmaps = pictures.map(({ width: w, height: h, data }, k) => {
    const maskRow = Math.ceil(w / 32) * 4, colors = w * h * 4;
    const bitmap = Buffer.alloc(40 + colors + maskRow * h);
    bitmap.writeUInt32LE(40, 0); // the header's size
    bitmap.writeInt32LE(w, 4);
    bitmap.writeInt32LE(2 * h, 8); // the colors and the mask, one on the other
    bitmap.writeUInt16LE(1, 12); // planes
    bitmap.writeUInt16LE(32, 14); // bits per pixel
    bitmap.writeUInt32LE(colors + maskRow * h, 20);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4, row = h - 1 - y;
      bitmap.set([data[i + 2], data[i + 1], data[i], data[i + 3]], 40 + (row * w + x) * 4);
      if (!data[i + 3]) bitmap[40 + colors + row * maskRow + (x >> 3)] |= 0x80 >> (x & 7);
    }
    const entry = 6 + 16 * k;
    head[entry] = w % 256; // 0 means 256
    head[entry + 1] = h % 256;
    head.writeUInt16LE(1, entry + 4);
    head.writeUInt16LE(32, entry + 6);
    head.writeUInt32LE(bitmap.length, entry + 8);
    head.writeUInt32LE(offset, entry + 12);
    offset += bitmap.length;
    return bitmap;
  });
  return Buffer.concat([head, ...bitmaps]);
};

// Writes a file in this folder unless it holds the same already: for a
// PNG, the same pixels.
const counts = { written: 0, unchanged: 0 };
const save = (name, bytes, png) => {
  const file = path.join(here, name);
  let same = false;
  if (fs.existsSync(file)) {
    const old = fs.readFileSync(file);
    if (png) {
      const was = PNG.sync.read(old);
      same = was.width === png.width && was.height === png.height && was.data.equals(png.data);
    } else {
      same = old.equals(Buffer.from(bytes));
    }
  }
  if (!same) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, bytes);
  }
  counts[same ? 'unchanged' : 'written']++;
  console.log(`${same ? 'unchanged' : 'written  '} logo/${name} (${(Buffer.byteLength(bytes) / 1024).toFixed(1)} KB)`);
};
// A PNG: RGBA with transparency (color type 6), or RGB when opaque (2).
const savePng = (name, png, colorType = 6) => save(name, PNG.sync.write(png, { colorType }), png);

// ---- The logo ------------------------------------------------------------

// Cells of 4 pixels, margins of 2 for the outline: the mark 44 × 44, the
// wordmark 216 × 40, the swash 44 × 44, and the lockup, the mark beside
// the wordmark, 270 × 44.
const logoOf = (set) => {
  const markShape = mark(4, 2), wordShape = wordmark(4, 2), swashShape = swash(40, 2);
  const markPicture = paint(markShape, set, dither(markShape, 'diagonal', set.bayer));
  const wordPicture = paint(wordShape, set, dither(wordShape, 'across', set.bayer));
  return {
    mark: markPicture,
    wordmark: wordPicture,
    lockup: beside(markPicture, 10, wordPicture),
    swash: paint(swashShape, set, dither(swashShape, 'diagonal', set.bayer)),
  };
};

const logos = sets.map((set) => {
  const logo = logoOf(set);
  for (const [name, picture] of Object.entries(logo)) {
    save(`${set.dir}/${name}.svg`, svgOf(picture));
    savePng(`${set.dir}/${name}.png`, picture);
    savePng(`${set.dir}/${name}@4x.png`, scaled(picture, 4));
  }
  return logo;
});

// For the web, in the ZX set, which works on any background (README.md).
// The favicon at 16, 32 and 48 pixels: 48 is the mark with 2 more pixels
// around; 32 is drawn with cells of 3 pixels; 16 with cells of 1, where
// 1-pixel strokes are too thin for a gradient, so its P and g are flat.
// The SVG icon is the 16-pixel one.
const [zx] = sets, [zxLogo] = logos;
const markOf3 = mark(3, 1);
const favicon16 = paint(mark(1, 3), zx, null);
save('favicon.ico', icoOf([favicon16, paint(markOf3, zx, dither(markOf3, 'diagonal', zx.bayer)), centered(zxLogo.mark, 48, 48)]));
save('icon.svg', svgOf(favicon16));
// For home screens on iPhones and iPads, 180 × 180 and opaque: the mark at
// 3 times on black. And GitHub's social preview, 1280 × 640: the lockup at
// 4 times on black.
savePng('apple-touch-icon.png', centered(scaled(zxLogo.mark, 3), 180, 180, [0, 0, 0]), 2);
savePng('social-preview.png', centered(scaled(zxLogo.lockup, 4), 1280, 640, [0, 0, 0]), 2);

console.log(`${counts.written} written, ${counts.unchanged} unchanged; ${runs} runs of the CLI.`);
