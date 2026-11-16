// What each gamma does to the test images, measured through the real CLI
// (the source of docs/gamma.md's tables). Writes markdown
// tables to stdout, and the dithered pictures to --out (default
// samples/gamma, gitignored), for looking at.
//
//   npm run build
//   node scripts/measure-gamma.mjs [--out <dir>]
//
// Method. A dithered picture is judged against its original the way an eye
// at a distance sees it: both are blurred (Gaussian, sigma 1.5 pixels), then
// compared as CIE L* for the grays and as CIELAB color difference (Delta E
// 1976) for color, the root mean square over the pixels, over the whole
// picture or the sphere tile. Two views of the blur, because the pictures
// are seen in two ways (docs/gamma.md, "Which value for which view"):
//
//   - light: the pixels' light is averaged, as the eye does at 1:1 from a
//     distance, the dots reaching it as they are;
//   - stored: the stored values are averaged, as a scaler that smooths does
//     (HiDPI screens, phones, a picture fitted into a page), and the
//     average then shown through sRGB's curve.
//
// Both use sRGB's own curve as the screen, whatever the gamma of the
// dithering: the gamma says what the dithering keeps, not what the screen
// is. The flat grays are dithered at 64 x 64, and the largest gray that
// still comes out all black is found by halving, checked at the ends.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { PNG } from 'pngjs';
import { COMPOSITES } from './lib/test-patterns.mjs';

const root = path.resolve(import.meta.dirname, '..');
const cli = path.join(root, 'cli', 'bin', 'puregrain-cli.mjs');
const generator = path.join(root, 'scripts', 'generate-images.mjs');

const { values } = parseArgs({ options: { out: { type: 'string', default: path.join(root, 'samples', 'gamma') } } });
const out = path.resolve(values.out);
const inputs = path.join(out, 'inputs');
fs.mkdirSync(inputs, { recursive: true });

const GAMMAS = ['off', '1.2', '1.5', '1.8', 'srgb'];
const GAMMA_LABELS = { off: 'off', '1.2': '1.2', '1.5': '1.5', '1.8': '1.8', srgb: 'sRGB' };

// ---- Running the CLI -------------------------------------------------------

const dither = (input, output, options) => {
  execFileSync(process.execPath, [cli, input, output, ...options], { stdio: ['ignore', 'pipe', 'inherit'] });
};

// ---- The screen: sRGB's curve, and CIELAB -----------------------------------

const toLinear = (c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const fromLinear = (l) => (l <= 0.0031308 ? 12.92 * l : 1.055 * l ** (1 / 2.4) - 0.055);
const LINEAR = Float64Array.from({ length: 256 }, (_, v) => toLinear(v / 255));

const D65 = { x: 0.95047, y: 1, z: 1.08883 };
const labF = (t) => (t > (6 / 29) ** 3 ? Math.cbrt(t) : t / (3 * (6 / 29) ** 2) + 4 / 29);
// CIELAB of a color given in linear light.
const lab = (r, g, b) => {
  const fx = labF((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / D65.x);
  const fy = labF((0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / D65.y);
  const fz = labF((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / D65.z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
};

// ---- Pictures and the blur --------------------------------------------------

const read = (file) => {
  const png = PNG.sync.read(fs.readFileSync(file));
  return { width: png.width, height: png.height, data: png.data };
};

// A Gaussian of sigma 1.5, to 5 pixels each way, normalized.
const KERNEL = (() => {
  const sigma = 1.5;
  const radius = 5;
  const w = Array.from({ length: 2 * radius + 1 }, (_, i) => Math.exp(-((i - radius) ** 2) / (2 * sigma * sigma)));
  const total = w.reduce((a, b) => a + b, 0);
  return w.map((x) => x / total);
})();

// Separable blur of one plane, the edges repeated.
const blur = (plane, width, height) => {
  const radius = (KERNEL.length - 1) / 2;
  const across = new Float64Array(plane.length);
  const result = new Float64Array(plane.length);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0;
      for (let k = -radius; k <= radius; k++) sum += KERNEL[k + radius] * plane[y * width + Math.min(width - 1, Math.max(0, x + k))];
      across[y * width + x] = sum;
    }
  }
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let sum = 0;
      for (let k = -radius; k <= radius; k++) sum += KERNEL[k + radius] * across[Math.min(height - 1, Math.max(0, y + k)) * width + x];
      result[y * width + x] = sum;
    }
  }
  return result;
};

// The picture as CIELAB after the blur, in a view: 'light' averages the
// light, 'stored' the stored values, shown through sRGB's curve.
const viewed = (picture, view) => {
  const { width, height, data } = picture;
  const n = width * height;
  const planes = [0, 1, 2].map((channel) => {
    const plane = new Float64Array(n);
    for (let i = 0; i < n; i++) plane[i] = view === 'light' ? LINEAR[data[4 * i + channel]] : data[4 * i + channel] / 255;
    return blur(plane, width, height);
  });
  const l = new Float64Array(n);
  const a = new Float64Array(n);
  const b = new Float64Array(n);
  for (let i = 0; i < n; i++) {
    const [r, g, bl] = planes.map((p) => (view === 'light' ? p[i] : toLinear(p[i])));
    [l[i], a[i], b[i]] = lab(r, g, bl);
  }
  return { width, height, l, a, b };
};

const originals = new Map();
const original = (file, view) => {
  const key = `${file}|${view}`;
  if (!originals.has(key)) originals.set(key, viewed(read(file), view));
  return originals.get(key);
};

// The root mean square of the color difference over a region (the whole
// picture by default).
const difference = (originalFile, outputFile, view, region) => {
  const want = original(originalFile, view);
  const got = viewed(read(outputFile), view);
  const { x0, y0, x1, y1 } = region ?? { x0: 0, y0: 0, x1: want.width, y1: want.height };
  let sum = 0;
  let count = 0;
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const i = y * want.width + x;
      sum += (want.l[i] - got.l[i]) ** 2 + (want.a[i] - got.a[i]) ** 2 + (want.b[i] - got.b[i]) ** 2;
      count++;
    }
  }
  return Math.sqrt(sum / count);
};

// A tile's box in a picture of the composite's layout, rounded as the
// generator rounds it.
const tileBox = (composite, tileId, width, height) => {
  const [, fx0, fy0, fx1, fy1] = COMPOSITES[composite].layout.find(([id]) => id === tileId);
  return { x0: Math.round(fx0 * width), y0: Math.round(fy0 * height), x1: Math.round(fx1 * width), y1: Math.round(fy1 * height) };
};

// The mean light of a gray picture, as a share of white's, and its mean
// stored value.
const brightness = (file) => {
  const { width, height, data } = read(file);
  let light = 0;
  let stored = 0;
  for (let i = 0; i < width * height; i++) {
    light += LINEAR[data[4 * i]];
    stored += data[4 * i];
  }
  return { light: (100 * light) / (width * height), stored: stored / (width * height) };
};

const table = (header, rows) => {
  const line = (cells) => `| ${cells.join(' | ')} |`;
  return [line(header), line(header.map((_, i) => (i === 0 ? ':---' : '---:'))), ...rows.map(line)].join('\n');
};
const two = (x) => x.toFixed(2);
const pair = (a, b) => `${two(a)} / ${two(b)}`;

// ---- The test images ---------------------------------------------------------

const generate = (...args) => execFileSync(process.execPath, [generator, ...args, '--out', inputs], { stdio: 'ignore' });
generate('--pattern', 'all', '--sizes', '512');
generate('--pattern', 'color', '--size', '256x192');
generate('--pattern', 'color', '--size', '320x200');
const GRAY = path.join(inputs, 'gray-512.png');
const COLOR = path.join(inputs, 'color-512.png');
const ZX = path.join(inputs, 'color-256x192.png');
const C64 = path.join(inputs, 'color-320x200.png');

const results = [];
const say = (text) => { results.push(text); };
const progress = (text) => process.stderr.write(`${text}\n`);

// ---- 1. Flat grays that come out all black ------------------------------------

{
  progress('flat grays');
  const flat = path.join(out, 'flat.png');
  const flatOut = path.join(out, 'flat-out.png');
  const whites = (value, options, gamma) => {
    const png = new PNG({ width: 64, height: 64 });
    for (let i = 0; i < 64 * 64; i++) png.data.set([value, value, value, 255], 4 * i);
    fs.writeFileSync(flat, PNG.sync.write(png, { colorType: 0 }));
    dither(flat, flatOut, [...options, '--gamma', gamma]);
    const result = read(flatOut);
    let n = 0;
    for (let i = 0; i < 64 * 64; i++) if (result.data[4 * i] === 255) n++;
    return n;
  };
  // The largest value whose flat gray is all black, by halving, then the
  // ends checked: the first value above has white, and so does 255.
  const allBlackUpTo = (options, gamma) => {
    let lo = 0;
    let hi = 255;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (whites(mid, options, gamma) === 0) lo = mid;
      else hi = mid;
    }
    const spot = [0, lo >> 1, lo].every((v) => whites(v, options, gamma) === 0);
    if (!spot || whites(hi, options, gamma) === 0) throw new Error(`the search for ${options.join(' ')} under ${gamma} isn't monotone`);
    return lo;
  };
  const halfLight = { off: 127.5, srgb: 255 * fromLinear(0.5) };
  const rows = GAMMAS.map((gamma) => [
    GAMMA_LABELS[gamma],
    (halfLight[gamma] ?? 255 * 0.5 ** (1 / Number(gamma))).toFixed(1),
    allBlackUpTo(['--bayer', '2'], gamma),
    allBlackUpTo(['--bayer', '4'], gamma),
    allBlackUpTo(['--kernel', 'atkinson'], gamma),
  ]);
  say('**Flat grays that come out all black** (the largest byte, at 64 × 64; Floyd–Steinberg and every kernel but Atkinson lose none):\n');
  say(table(['Gamma', 'Half the light at byte', 'Bayer 2', 'Bayer 4', 'Atkinson'], rows) + '\n');
  fs.rmSync(flat);
  fs.rmSync(flatOut);
}

// ---- 2. The gray composite ----------------------------------------------------

const picture = (name, input, options, gamma) => {
  const file = path.join(out, `${name}-${gamma}.png`);
  dither(input, file, [...options, '--gamma', gamma]);
  return file;
};

{
  progress('gray composite');
  const METHODS = [
    ['Floyd–Steinberg', 'gray-fs', ['--threshold', '128', '--kernel', 'floyd-steinberg']],
    ['Atkinson', 'gray-atkinson', ['--threshold', '128', '--kernel', 'atkinson']],
    ['Bayer 2', 'gray-bayer2', ['--bayer', '2']],
    ['Bayer 4', 'gray-bayer4', ['--bayer', '4']],
    ['4 levels, Floyd–Steinberg', 'gray-levels4-fs', ['--levels', '4', '--kernel', 'floyd-steinberg']],
  ];
  const files = Object.fromEntries(GAMMAS.map((gamma) => [gamma, METHODS.map(([, name, options]) => picture(name, GRAY, options, gamma))]));
  const rows = GAMMAS.map((gamma) => [
    GAMMA_LABELS[gamma],
    ...files[gamma].map((file) => pair(difference(GRAY, file, 'light'), difference(GRAY, file, 'stored'))),
  ]);
  say('**The gray composite, black and white** (512²; error in L* after blurring, RMS, as: viewed in light / viewed on stored values):\n');
  say(table(['Gamma', ...METHODS.map(([label]) => label)], rows) + '\n');
  const base = brightness(GRAY);
  const shown = GAMMAS.map((gamma) => {
    const b = brightness(files[gamma][0]);
    return [GAMMA_LABELS[gamma], b.light.toFixed(1), b.stored.toFixed(1)];
  });
  say(`**What Floyd–Steinberg's picture gives off** (the original: ${base.light.toFixed(1)}% of white's light, mean stored value ${base.stored.toFixed(1)}):\n`);
  say(table(['Gamma', 'Light, % of white', 'Mean stored value'], shown) + '\n');
}

// ---- 3. The color composite ----------------------------------------------------

{
  progress('color composite');
  const box = tileBox('color', 'color:sphere', 512, 512);
  const METHODS = [
    ['Floyd–Steinberg', 'color-levels4-fs', ['--levels', '4', '--kernel', 'floyd-steinberg']],
    ['Atkinson', 'color-levels4-atkinson', ['--levels', '4', '--kernel', 'atkinson']],
  ];
  const rows = GAMMAS.map((gamma) => {
    const cells = METHODS.flatMap(([, name, options]) => {
      const file = picture(name, COLOR, options, gamma);
      return ['light', 'stored'].map((view) => `${two(difference(COLOR, file, view))} / ${two(difference(COLOR, file, view, box))}`);
    });
    return [GAMMA_LABELS[gamma], ...cells];
  });
  say('**The color composite, 4 levels per channel** (512²; ΔE after blurring, RMS, as: whole picture / the sphere):\n');
  say(table(['Gamma', ...METHODS.flatMap(([label]) => [`${label}, in light`, `${label}, stored`])], rows) + '\n');
}

// ---- 4. The machine screens ------------------------------------------------------

{
  progress('machine screens');
  const MACHINES = [['ZX Spectrum', 'zx-spectrum', 'zx', ZX], ['C64', 'c64-hires', 'c64', C64]];
  const METHODS = [['Bayer 2', 'bayer2', ['--bayer', '2']], ['Bayer 4', 'bayer4', ['--bayer', '4']], ['Atkinson', 'atkinson', ['--kernel', 'atkinson']]];
  const rows = GAMMAS.map((gamma) => [
    GAMMA_LABELS[gamma],
    ...MACHINES.flatMap(([, machine, short, input]) => METHODS.map(([, method, options]) => {
      const file = picture(`${short}-${method}`, input, ['--machine', machine, ...options], gamma);
      return pair(difference(input, file, 'light'), difference(input, file, 'stored'));
    })),
  ]);
  say('**The machine screens** (the test image at the screen\'s size; ΔE after blurring, RMS over the whole picture, as: viewed in light / viewed on stored values):\n');
  say(table(['Gamma', ...MACHINES.flatMap(([label]) => METHODS.map(([method]) => `${label}, ${method}`))], rows) + '\n');
}

console.log(results.join('\n'));
