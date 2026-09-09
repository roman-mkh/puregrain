import fs from 'node:fs';
import path from 'node:path';
import { PNG } from 'pngjs';

const SIZES = [64, 128, 256, 512, 1024];
const OUTPUT_DIR = path.join(import.meta.dirname, '..', 'samples', 'bench');

// Same content pattern as the original PIL-based generator: a horizontal
// gradient background plus a shaded circle, scaled proportionally to each
// image size, so results are comparable across sizes (content complexity
// scales with N, not the algorithm's characteristics).
function renderBenchImage(size) {
  const png = new PNG({ width: size, height: size });

  const cx = size * 0.74;
  const cy = size * 0.27;
  const r = size * 0.2;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      // horizontal gradient: 0 (black) at x=0, 255 (white) at x=size-1
      let v = Math.round((255 * x) / (size - 1));

      // radial-shaded circle, overrides the gradient where it applies
      const d = Math.hypot(x - cx, y - cy) / r;
      if (d <= 1) {
        v = Math.round(255 * Math.pow(Math.max(0, 1 - d), 0.5));
      }

      const idx = (y * size + x) * 4;
      png.data[idx] = v;
      png.data[idx + 1] = v;
      png.data[idx + 2] = v;
      png.data[idx + 3] = 255;
    }
  }

  return png;
}

function main() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  for (const size of SIZES) {
    const png = renderBenchImage(size);
    const outPath = path.join(OUTPUT_DIR, `bench-${size}.png`);
    fs.writeFileSync(outPath, PNG.sync.write(png));
    console.log(`Wrote ${outPath} (${size}x${size})`);
  }
}

main();