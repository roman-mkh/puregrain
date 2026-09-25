// PNG input/output for the CLI — the only part that has to be JS: there's
// no maintained PureScript PNG codec, so this wraps pngjs.

import fs from 'node:fs';
import { PNG } from 'pngjs';

// Every channel written is rounded and clamped to [0,255] here: png.data is
// a byte buffer, and a raw assignment would truncate fractions and wrap
// out-of-range values modulo 256 (256 -> 0, -1 -> 255).
const toByte = (v) => Math.min(255, Math.max(0, Math.round(v)));

export const readRgbRows = (path) => () => {
  let png;
  try {
    png = PNG.sync.read(fs.readFileSync(path));
  } catch (err) {
    const hint = err.code === 'ENOENT' ? ' (if it is a generated test image: npm run generate-images)' : '';
    throw new Error(`Cannot read PNG "${path}": ${err.message}${hint}`);
  }
  // pngjs always decodes to RGBA, whatever the file's own color type.
  // Alpha is ignored: the CLI dithers the stored color values.
  const { width, height, data } = png;
  const rows = new Array(height);
  for (let y = 0; y < height; y++) {
    const row = new Array(width);
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      row[x] = { r: data[i], g: data[i + 1], b: data[i + 2] };
    }
    rows[y] = row;
  }
  return rows;
};

// The output color type goes to PNG.sync.write itself: pngjs's sync
// writer ignores the colorType given to the PNG constructor.
function writeRows(path, rows, colorType, setPixel) {
  const height = rows.length;
  const width = height > 0 ? rows[0].length : 0;
  const png = new PNG({ width, height });
  for (let y = 0; y < height; y++) {
    const row = rows[y];
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      setPixel(png.data, i, row[x]);
      png.data[i + 3] = 255;
    }
  }
  try {
    fs.writeFileSync(path, PNG.sync.write(png, { colorType }));
  } catch (err) {
    throw new Error(`Cannot write PNG "${path}": ${err.message}`);
  }
}

export const writeGrayRows = (path) => (rows) => () =>
  writeRows(path, rows, 0, (data, i, v) => {
    const b = toByte(v);
    data[i] = b;
    data[i + 1] = b;
    data[i + 2] = b;
  });

export const writeRgbRows = (path) => (rows) => () =>
  writeRows(path, rows, 2, (data, i, p) => {
    data[i] = toByte(p.r);
    data[i + 1] = toByte(p.g);
    data[i + 2] = toByte(p.b);
  });

// High-resolution monotonic clock, in milliseconds.
export const nowMs = () => performance.now();
