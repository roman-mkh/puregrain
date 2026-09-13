import fs from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';

import { ditherImageArray } from '../output/Dither.Ffi/index.js';
import { floydSteinberg, atkinson, jarvisJudiceNinke } from '../output/Dither.Kernel/index.js';

const KERNELS = {
  'floyd-steinberg': floydSteinberg,
  'atkinson': atkinson,
  'jjn': jarvisJudiceNinke,
};

function parseArgs(argv) {
  const [inputPath, outputPath, kernelName = 'floyd-steinberg', thresholdStr = '128'] = argv;
  if (!inputPath || !outputPath) {
    console.error('Usage: node dither-cli.mjs <input.png> <output.png> [kernel] [threshold]');
    console.error(`  kernel: one of ${Object.keys(KERNELS).join(', ')} (default: floyd-steinberg)`);
    process.exit(1);
  }
  const kernel = KERNELS[kernelName];
  if (!kernel) {
    console.error(`Unknown kernel "${kernelName}". Available: ${Object.keys(KERNELS).join(', ')}`);
    process.exit(1);
  }
  const threshold = Number(thresholdStr);
  return { inputPath, outputPath, kernel, threshold };
}

function readGrayscaleRows(pngPath) {
  const png = PNG.sync.read(fs.readFileSync(pngPath));
  const { width, height, data } = png;
  const rows = [];
  for (let y = 0; y < height; y++) {
    const row = new Array(width);
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const r = data[idx];
      const g = data[idx + 1];
      const b = data[idx + 2];
      row[x] = 0.299 * r + 0.587 * g + 0.114 * b;
    }
    rows.push(row);
  }
  return { width, height, rows };
}

function writeGrayscaleRows(pngPath, width, height, rows) {
  const png = new PNG({ width, height, colorType: 0 });
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = (y * width + x) * 4;
      const v = rows[y][x];
      png.data[idx] = v;
      png.data[idx + 1] = v;
      png.data[idx + 2] = v;
      png.data[idx + 3] = 255;
    }
  }
  fs.writeFileSync(pngPath, PNG.sync.write(png));
}

function main() {
  const { inputPath, outputPath, kernel, threshold } = parseArgs(process.argv.slice(2));

  const { width, height, rows } = readGrayscaleRows(inputPath);
  console.log(`Read ${path.basename(inputPath)}: ${width}x${height}`);

  const quantize = (x) => (x < threshold ? 0.0 : 255.0);
  const resultRows = ditherImageArray(kernel)(quantize)(rows);

  writeGrayscaleRows(outputPath, width, height, resultRows);
  console.log(`Wrote ${path.basename(outputPath)}`);
}

main();