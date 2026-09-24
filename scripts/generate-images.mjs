// Generates the test images used both for visual dithering checks and for
// benchmarks. What each image and tile is for, and what to look for in
// the dithered output: docs/test-images.md.

import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { PNG } from 'pngjs';
import { COMPOSITES, TILES, findTile, patternOf, renderComposite, renderTile } from './lib/test-patterns.mjs';

const USAGE = `Usage: node scripts/generate-images.mjs [options]

  --pattern <p>   all (default), ${Object.keys(COMPOSITES).join(', ')}, or a single tile id
                  (rendered full-frame on its own; see --list)
  --size <s>      N (square) or WxH, e.g. 512 or 1024x256 (default: 512)
  --sizes <list>  several sizes at once, comma-separated, e.g. 64,128,1024x256
  --out <dir>     output directory (default: samples)
  --list          list the composites and their tiles, then exit
  --help          show this help`;

const COLOR_TYPE_NAMES = { 0: 'grayscale', 2: 'RGB' };

function fail(message) {
  console.error(`${message}\n\n${USAGE}`);
  process.exit(1);
}

function parseSize(spec) {
  const match = /^(\d+)(?:x(\d+))?$/.exec(spec.trim());
  if (!match) fail(`Invalid size "${spec}": expected N (square) or WxH, e.g. 512 or 1024x256.`);
  const width = Number(match[1]);
  const height = match[2] === undefined ? width : Number(match[2]);
  if (width < 1 || height < 1) fail(`Invalid size "${spec}": width and height must be at least 1.`);
  // Square sizes get the short label, however they were written.
  return { width, height, label: width === height ? `${width}` : `${width}x${height}` };
}

// A pattern name -> the images to render: each a file-name stem, a
// render function, and the PNG color type to write it with.
function jobsFor(pattern) {
  if (pattern === 'all') return Object.keys(COMPOSITES).flatMap(jobsFor);
  if (COMPOSITES[pattern]) {
    return [{
      stem: pattern,
      render: (w, h) => renderComposite(pattern, w, h),
      colorType: COMPOSITES[pattern].colorType,
    }];
  }
  if (findTile(pattern)) {
    return [{
      stem: pattern.replace(':', '-'),
      render: (w, h) => renderTile(pattern, w, h),
      colorType: COMPOSITES[patternOf(pattern)].colorType,
    }];
  }
  fail(`Unknown pattern "${pattern}". Use all, ${Object.keys(COMPOSITES).join(', ')}, or a tile id (see --list).`);
}

function printList() {
  const idWidth = Math.max(...TILES.map((t) => t.id.length));
  for (const [name, composite] of Object.entries(COMPOSITES)) {
    console.log(`${name}: ${composite.description} (${COLOR_TYPE_NAMES[composite.colorType]} PNG)`);
    for (const [id] of composite.layout) {
      console.log(`  ${id.padEnd(idWidth)}  ${findTile(id).description}`);
    }
    console.log();
  }
  console.log('Details and what to look for: docs/test-images.md');
}

function main() {
  let values;
  try {
    ({ values } = parseArgs({
      options: {
        pattern: { type: 'string', default: 'all' },
        size: { type: 'string' },
        sizes: { type: 'string' },
        out: { type: 'string', default: 'samples' },
        list: { type: 'boolean', default: false },
        help: { type: 'boolean', short: 'h', default: false },
      },
    }));
  } catch (err) {
    fail(err.message);
  }

  if (values.help) {
    console.log(USAGE);
    return;
  }
  if (values.list) {
    printList();
    return;
  }
  if (values.size !== undefined && values.sizes !== undefined) {
    fail('Use either --size or --sizes, not both.');
  }

  const sizeSpecs = values.sizes !== undefined ? values.sizes.split(',') : [values.size ?? '512'];
  const sizes = sizeSpecs.map(parseSize);
  const jobs = jobsFor(values.pattern);

  fs.mkdirSync(values.out, { recursive: true });
  for (const { width, height, label } of sizes) {
    for (const job of jobs) {
      const file = path.join(values.out, `${job.stem}-${label}.png`);
      const png = job.render(width, height);
      fs.writeFileSync(file, PNG.sync.write(png, { colorType: job.colorType }));
      console.log(`Wrote ${file} (${width}x${height}, ${COLOR_TYPE_NAMES[job.colorType]})`);
    }
  }
}

main();
