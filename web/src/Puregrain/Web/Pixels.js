// A picture's pixels in the browser: RGBA bytes, row after row, in a
// Uint8ClampedArray, as a canvas's ImageData holds them.

// Each channel written is rounded and clamped as the CLI writes its PNGs
// (cli/src/Puregrain/Cli/Png.js), so both give the same bytes.
const toByte = (v) => Math.min(255, Math.max(0, Math.round(v)));

export const readRow = (pixels) => (width) => (y) => () => {
  const row = new Array(width);
  for (let x = 0, i = y * width * 4; x < width; x++, i += 4) {
    row[x] = { r: pixels[i], g: pixels[i + 1], b: pixels[i + 2] };
  }
  return row;
};

export const writeRgbRow = (pixels) => (width) => (y) => (row) => () => {
  for (let x = 0, i = y * width * 4; x < width; x++, i += 4) {
    const p = row[x];
    pixels[i] = toByte(p.r);
    pixels[i + 1] = toByte(p.g);
    pixels[i + 2] = toByte(p.b);
    pixels[i + 3] = 255;
  }
};

export const writeGrayRow = (pixels) => (width) => (y) => (row) => () => {
  for (let x = 0, i = y * width * 4; x < width; x++, i += 4) {
    const v = toByte(row[x]);
    pixels[i] = v;
    pixels[i + 1] = v;
    pixels[i + 2] = v;
    pixels[i + 3] = 255;
  }
};

export const allNeutral = (pixels) => () => {
  for (let i = 0; i < pixels.length; i += 4) {
    if (pixels[i] !== pixels[i + 1] || pixels[i + 1] !== pixels[i + 2]) return false;
  }
  return true;
};

export const newPixels = (length) => () => new Uint8ClampedArray(length);

export const copyPixels = (pixels) => () => new Uint8ClampedArray(pixels);

export const transferable = (pixels) => pixels.buffer;

export const toImageData = (pixels) => (width) => (height) => () =>
  new ImageData(pixels, width, height);
