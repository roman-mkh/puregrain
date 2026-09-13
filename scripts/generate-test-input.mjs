import fs from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';
import {
  drawHorizontalGradient,
  drawShadedCircle,
  drawFlatToneBands,
  drawRect,
  drawLine,
} from './lib/test-patterns.mjs';

const SIZE = 256;
const OUTPUT_PATH = path.join(import.meta.dirname, '..', 'samples', 'test-input.png');

function main() {
  const png = new PNG({ width: SIZE, height: SIZE, colorType: 0 });

  drawHorizontalGradient(png);
  drawShadedCircle(png, 190, 70, 50);

  const levels = [0, 32, 64, 96, 128, 160, 192, 224, 255];
  drawFlatToneBands(png, levels, SIZE - 40, SIZE);

  drawRect(png, 10, 120, 90, 180, 0);
  drawRect(png, 100, 120, 180, 180, 255);
  drawLine(png, 10, 120, 180, 180, 128);

  fs.mkdirSync(path.dirname(OUTPUT_PATH), { recursive: true });
  fs.writeFileSync(OUTPUT_PATH, PNG.sync.write(png));
  console.log(`Wrote ${OUTPUT_PATH} (${SIZE}x${SIZE})`);
}

main();