// End-to-end checks of the web UI in real browsers, Chromium, Firefox and
// WebKit: the exact parts of the manual checklist (web/README.md,
// "Checking a change by hand"). For five settings, one for each kind of
// colors and one of the newer kernels, the downloaded PNG has the CLI's
// pixel values; for both
// machines, at their screens' sizes, the PNG too, and their files are the
// CLI's, byte for byte; the split shows the original left of it and the
// result right of it, exact to the screen pixel, dragging its handle
// selects nothing, and a click on "Original" or "Result" moves it to its
// end; a run works with worker.js blocked once the page has loaded.
//
// The browsers run in Playwright's Docker image, of the installed
// playwright-core's version. Inside the container,
// scripts/lib/check-web-container.mjs serves the page and starts
// Playwright's server, which this script drives from the host. Needs
// Docker, usable without sudo; the first run downloads the image (about
// 1 GB compressed). Build first (npm run build, npm run web:build).
// Outputs go to samples/check-web/ (gitignored). Runs every check, then
// exits non-zero if any failed, so one run shows every difference.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';
import { chromium, firefox, webkit } from 'playwright-core';
import { PNG } from 'pngjs';

process.chdir(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));
const out = 'samples/check-web';
const pageUrl = 'http://localhost:8080/';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

if (!fs.existsSync('web/dist/index.html')) {
  console.error('The page is not built yet. Run: npm run web:build');
  process.exit(1);
}
if (spawnSync('docker', ['version'], { stdio: 'ignore' }).status !== 0) {
  console.error('check:web needs Docker, running and usable without sudo.');
  process.exit(1);
}

// The pictures, and the CLI's results for them.
const SETTINGS = [
  { what: 'a threshold, Floyd-Steinberg', colors: 'threshold', kernel: 'floyd-steinberg',
    cli: ['--threshold', '128', '--kernel', 'floyd-steinberg'], name: 'threshold128-floyd-steinberg' },
  { what: '4 levels, Atkinson', colors: 'levels', levels: '4', kernel: 'atkinson',
    cli: ['--levels', '4', '--kernel', 'atkinson'], name: 'levels4-atkinson' },
  { what: 'the CGA palette, JJN', colors: 'cga16', kernel: 'jjn',
    cli: ['--palette', 'cga16', '--kernel', 'jjn'], name: 'cga16-jjn' },
  { what: '4 levels, Bayer 4', colors: 'levels', levels: '4', bayer: '4',
    cli: ['--levels', '4', '--bayer', '4'], name: 'levels4-bayer4' },
  // One of the kernels of the library's 0.2.1, the one of the most unusual
  // shape: it reaches three columns to the left (v2.2 in web/ROADMAP.md).
  { what: '4 levels, Shiau-Fan 2', colors: 'levels', levels: '4', kernel: 'shiau-fan-2',
    cli: ['--levels', '4', '--kernel', 'shiau-fan-2'], name: 'levels4-shiau-fan-2' },
];
const MACHINES = [
  { what: 'the ZX Spectrum, Bayer 8', picture: 'color-256x192', target: 'zx-spectrum', formats: ['png', 'scr', 'tap'] },
  { what: 'the C64, Bayer 8', picture: 'color-320x200', target: 'c64-hires', formats: ['png', 'prg', 'art'] },
];
const PICTURE = 'color-320x200';

fs.rmSync(out, { recursive: true, force: true });
for (const dir of ['downloads', ...MACHINES.map((m) => m.target)]) fs.mkdirSync(`${out}/${dir}`, { recursive: true });
for (const size of ['320x200', '256x192']) {
  execFileSync('node', ['scripts/generate-images.mjs', '--pattern', 'color', '--size', size, '--out', out]);
}
const cli = (input, output, options) => execFileSync('node', ['cli/bin/puregrain-cli.mjs', input, output, ...options]);
for (const s of SETTINGS) cli(`${out}/${PICTURE}.png`, `${out}/cli-${s.name}.png`, s.cli);
// The tape's name comes from the output file's name: the picture's, as on the page.
for (const m of MACHINES) {
  for (const format of m.formats) {
    cli(`${out}/${m.picture}.png`, `${out}/${m.target}/${m.picture}.${format}`, ['--machine', m.target, '--bayer', '8']);
  }
}

// The container: the image's version is playwright-core's.
const { version } = JSON.parse(fs.readFileSync('node_modules/playwright-core/package.json', 'utf8'));
const image = `mcr.microsoft.com/playwright:v${version}-noble`;
const container = `puregrain-check-web-${process.pid}`;
const removeContainer = () => spawnSync('docker', ['rm', '--force', container], { stdio: 'ignore' });
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    removeContainer();
    process.exit(130);
  });
}

let checks = 0;
let failures = 0;
const report = (good, text) => {
  checks++;
  if (!good) failures++;
  console.log(`${good ? 'PASS' : 'FAIL'}  ${text}`);
};

const pixelsOf = (bytes) => PNG.sync.read(bytes);
// How many pixels differ in their color, or why they can't be compared.
const differing = (got, want) => {
  if (got.width !== want.width || got.height !== want.height) {
    return `${got.width}×${got.height}, not ${want.width}×${want.height}`;
  }
  let count = 0;
  for (let i = 0; i < want.data.length; i += 4) {
    if (got.data[i] !== want.data[i] || got.data[i + 1] !== want.data[i + 1] || got.data[i + 2] !== want.data[i + 2]) count++;
  }
  return count;
};

// Each run of the page is a new worker: the check counts them, and notes
// when each has answered with its result (or an error).
const recordRuns = () => {
  const Original = window.Worker;
  window.__runs = [];
  window.Worker = function (...args) {
    const worker = new Original(...args);
    const run = { ended: false };
    window.__runs.push(run);
    worker.addEventListener('message', (event) => {
      if (event.data && event.data.kind !== 'progress') run.ended = true;
    });
    return worker;
  };
};

const checksIn = async (engine, page) => {
  const runs = () => page.evaluate(() => window.__runs.length);
  // Waits for a run started after `before` runs, the last one, to end,
  // and for the page to show its result.
  const finished = async (before, timeout = 120000) => {
    await page.waitForFunction((n) => window.__runs.length > n && window.__runs[window.__runs.length - 1].ended, before, { timeout });
    await page.waitForFunction(() => {
      const button = document.querySelector('.downloads button');
      return button !== null && !button.disabled && document.querySelector('.progress:not([hidden])') === null;
    });
  };
  const open = async (picture) => {
    await page.goto(pageUrl);
    await page.locator('input[type=file]').first().setInputFiles(`${out}/${picture}.png`);
    await page.waitForFunction((name) => document.querySelector('.picture-name')?.textContent === name, `${picture}.png`);
  };
  // The segments and cards are radio buttons; one is picked once it's available.
  const pick = async (name, value) => {
    const selector = `input[name="${name}"][value="${value}"]`;
    await page.waitForFunction((s) => document.querySelector(s)?.disabled === false, selector);
    await page.locator(selector).evaluate((radio) => radio.click());
  };
  const download = async (click) => {
    const [file] = await Promise.all([page.waitForEvent('download'), click()]);
    const saved = `${out}/downloads/${engine}-${file.suggestedFilename()}`;
    await file.saveAs(saved);
    return { name: file.suggestedFilename(), bytes: fs.readFileSync(saved) };
  };
  const fromList = (format) => async () => {
    if (await page.locator('.formats').isHidden()) await page.locator('.downloads button.more').click();
    await page.locator('.formats button', { has: page.locator('.ext', { hasText: `.${format}` }) }).click();
  };

  // The split set by the keys: Home, then Shift+→ for tens and → for ones.
  const checkSplit = async (original, result, split) => {
    await page.locator('.handle').focus();
    await page.keyboard.press('Home');
    for (let i = 0; i < Math.floor(split / 10); i++) await page.keyboard.press('Shift+ArrowRight');
    for (let i = 0; i < split % 10; i++) await page.keyboard.press('ArrowRight');
    // The handle's line and the labels hidden for the comparison.
    const style = await page.addStyleTag({ content: '.handle, .sides { visibility: hidden !important; }' });
    await sleep(100);
    const g = await page.evaluate(() => {
      const c = document.querySelector('canvas.result').getBoundingClientRect();
      const v = document.querySelector('.view').getBoundingClientRect();
      return { x: c.x, y: c.y, vx: v.x, vy: v.y, vw: v.width, vh: v.height, inner: window.innerWidth,
        now: Number(document.querySelector('.handle').getAttribute('aria-valuenow')) };
    });
    const shot = PNG.sync.read(await page.screenshot());
    await style.evaluate((element) => element.remove());
    const scale = shot.width / g.inner;
    const { width, height } = original;
    const x1 = Math.min(shot.width, Math.floor((g.vx + g.vw) * scale));
    const y1 = Math.min(shot.height, Math.floor((g.vy + g.vh) * scale));
    const top = Math.max(0, Math.ceil(g.vy * scale));
    // The canvas's corner may round either way to a screen pixel.
    let best = null;
    for (const ox of [-1, 0, 1]) {
      for (const oy of [-1, 0, 1]) {
        const x0 = Math.round(g.x * scale) + ox;
        const y0 = Math.round(g.y * scale) + oy;
        let compared = 0;
        let differ = 0;
        for (let sy = Math.max(y0, top); sy < Math.min(y0 + height, y1); sy++) {
          for (let sx = x0; sx < Math.min(x0 + width, x1); sx++) {
            const col = sx - x0;
            const want = col < split ? original : result;
            const i = ((sy - y0) * width + col) * 4;
            const j = (sy * shot.width + sx) * 4;
            compared++;
            if (want.data[i] !== shot.data[j] || want.data[i + 1] !== shot.data[j + 1] || want.data[i + 2] !== shot.data[j + 2]) differ++;
          }
        }
        if (best === null || differ < best.differ) best = { compared, differ };
      }
    }
    report(best.differ === 0 && best.compared === width * height && g.now === split,
      `${engine}: the split at column ${split} (the handle says ${g.now}): ${best.compared} screen pixels, ${best.differ} differ`);
  };

  // WebKit stretched a text selection from the pressed handle over the
  // pictures and the page's text while the handle was dragged (Safari 16.6,
  // 2026-11-02): a drag far out of the picture, three ways, selects nothing.
  const checkDragSelects = async () => {
    const found = [];
    for (const [where, x, y] of [['left', 5, null], ['left and down', 5, 1095], ['right and up', 1595, 5]]) {
      await page.evaluate(() => window.getSelection().removeAllRanges());
      const knob = await page.locator('.knob').boundingBox();
      const from = { x: knob.x + knob.width / 2, y: knob.y + knob.height / 2 };
      await page.mouse.move(from.x, from.y);
      await page.mouse.down();
      await page.mouse.move(x, y ?? from.y, { steps: 40 });
      const selection = await page.evaluate(() => ({ none: window.getSelection().isCollapsed, text: window.getSelection().toString() }));
      await page.mouse.up();
      if (!selection.none) found.push(`${where}: ${JSON.stringify(selection.text.trim().slice(0, 30))}`);
    }
    report(found.length === 0,
      `${engine}: dragging the split's handle far out of the picture selects nothing${found.length === 0 ? '' : ` (it selected, dragged ${found.join('; ')})`}`);
  };

  // The runs' workers start from the page's copy of worker.js in memory:
  // with the file blocked once the page has fetched it, a run still gives
  // the CLI's pixels (started from the file, no run worked without it).
  const checkWorkerInMemory = async () => {
    const fetched = page.waitForResponse((r) => r.url().endsWith('/worker.js'), { timeout: 10000 }).catch(() => null);
    await page.goto(pageUrl);
    await fetched;
    await sleep(300);
    await page.context().route('**/worker.js', (route) => route.abort());
    try {
      await page.locator('input[type=file]').first().setInputFiles(`${out}/${PICTURE}.png`);
      await page.waitForFunction((name) => document.querySelector('.picture-name')?.textContent === name, `${PICTURE}.png`);
      const before = await runs();
      await page.locator('select').nth(0).selectOption('levels');
      await page.locator('.stepper input[type=number]').fill('4');
      await page.locator('select').nth(1).selectOption('atkinson');
      const done = await finished(before, 20000).then(() => true, () => false);
      const diff = done
        ? differing(pixelsOf((await download(() => page.locator('.downloads button').first().click())).bytes), pixelsOf(fs.readFileSync(`${out}/cli-levels4-atkinson.png`)))
        : null;
      report(done && diff === 0,
        `${engine}: with worker.js blocked after the page has loaded, a run ${done ? (diff === 0 ? "still gives the CLI's pixels" : `gives ${diff} pixels off`) : 'never finishes'}`);
    } finally {
      await page.context().unroute('**/worker.js');
    }
  };

  // A click on "Result" shows the whole result, on "Original" the whole
  // original: the split goes to 0 and to the width.
  const checkLabels = async (width) => {
    const split = () => page.evaluate(() => Number(document.querySelector('.handle').getAttribute('aria-valuenow')));
    await page.locator('.sides span', { hasText: 'Result' }).click({ timeout: 5000 });
    const toResult = await split();
    await page.locator('.sides span', { hasText: 'Original' }).click({ timeout: 5000 });
    const toOriginal = await split();
    report(toResult === 0 && toOriginal === width,
      `${engine}: a click on "Result" moves the split to ${toResult}, on "Original" to ${toOriginal} (the width, ${width})`);
  };

  for (const s of SETTINGS) {
    await open(PICTURE);
    const before = await runs();
    await page.locator('select').nth(0).selectOption(s.colors);
    if (s.levels) await page.locator('.stepper input[type=number]').fill(s.levels);
    if (s.kernel) await page.locator('select').nth(1).selectOption(s.kernel);
    if (s.bayer) await pick('bayer', s.bayer);
    await finished(before);
    const expected = `${PICTURE}-${s.name}.png`;
    const file = await download(() => page.locator('.downloads button').first().click());
    const diff = differing(pixelsOf(file.bytes), pixelsOf(fs.readFileSync(`${out}/cli-${s.name}.png`)));
    report(file.name === expected && diff === 0,
      `${engine}: ${s.what}: ${file.name}${file.name === expected ? '' : ` (not ${expected})`}, ${diff === 0 ? "the CLI's pixels" : `${diff} pixels differ from the CLI's`}`);
    if (s.name === 'levels4-atkinson') {
      const original = pixelsOf(fs.readFileSync(`${out}/${PICTURE}.png`));
      const result = pixelsOf(fs.readFileSync(`${out}/cli-${s.name}.png`));
      for (const split of [160, 0, 320, 1, 37, 319]) await checkSplit(original, result, split);
      await checkDragSelects();
      await checkLabels(original.width);
    }
  }

  for (const m of MACHINES) {
    await open(m.picture);
    const before = await runs();
    await pick('target', m.target);
    await pick('bayer', '8');
    await finished(before);
    for (const format of m.formats) {
      const expected = `${m.picture}-${m.target}-bayer8.${format}`;
      const file = await download(fromList(format));
      const reference = fs.readFileSync(`${out}/${m.target}/${m.picture}.${format}`);
      const diff = format === 'png' ? differing(pixelsOf(file.bytes), pixelsOf(reference)) : null;
      const same = format === 'png' ? diff === 0 : file.bytes.equals(reference);
      const how = format === 'png'
        ? (diff === 0 ? "the CLI's pixels" : `${diff} pixels differ from the CLI's`)
        : (same ? "the CLI's file, byte for byte" : `not the CLI's file (${file.bytes.length} bytes, the CLI's ${reference.length})`);
      report(file.name === expected && same, `${engine}: ${m.what}: ${file.name}${file.name === expected ? '' : ` (not ${expected})`}, ${how}`);
    }
  }

  await checkWorkerInMemory();
};

const started = Date.now();
try {
  if (spawnSync('docker', ['image', 'inspect', image], { stdio: 'ignore' }).status !== 0) {
    console.log(`Downloading ${image}, once for each version of Playwright…`);
    execFileSync('docker', ['pull', image], { stdio: 'inherit' });
  }
  const mount = (from, to) => ['--volume', `${path.resolve(from)}:${to}:ro`];
  execFileSync('docker', ['run', '--detach', '--init', '--ipc=host', '--name', container,
    '--user', 'pwuser', '--workdir', '/home/pwuser', '--publish', '127.0.0.1::3000',
    ...mount('node_modules/playwright-core', '/opt/playwright-core'),
    ...mount('web/dist', '/opt/site'),
    ...mount('scripts/lib/check-web-container.mjs', '/opt/check-web-container.mjs'),
    image, 'node', '/opt/check-web-container.mjs'], { stdio: 'ignore' });
  const port = /:(\d+)\s*$/m.exec(execFileSync('docker', ['port', container, '3000/tcp'], { encoding: 'utf8' }))[1];
  const logs = () => {
    const { stdout, stderr } = spawnSync('docker', ['logs', container], { encoding: 'utf8' });
    return `${stdout}${stderr}`;
  };
  for (let waited = 0; !/Listening on/.test(logs()); waited += 200) {
    if (waited > 60000) throw new Error(`Playwright's server didn't start:\n${logs()}`);
    await sleep(200);
  }
  const endpoint = `ws://127.0.0.1:${port}/`;

  for (const [engine, type] of [['Chromium', chromium], ['Firefox', firefox], ['WebKit', webkit]]) {
    const begun = Date.now();
    const browser = await type.connect(endpoint, { timeout: 60000 });
    console.log(`== ${engine} ${browser.version()}`);
    try {
      const context = await browser.newContext({ viewport: { width: 1600, height: 1100 }, deviceScaleFactor: 1, acceptDownloads: true });
      await context.addInitScript(recordRuns);
      await checksIn(engine, await context.newPage());
    } catch (error) {
      report(false, `${engine}: the checks stopped: ${error.message.split('\n')[0]}`);
    } finally {
      await browser.close();
    }
    console.log(`   (${((Date.now() - begun) / 1000).toFixed(1)} s)`);
  }
} finally {
  removeContainer();
}

console.log(failures === 0
  ? `check:web: all ${checks} checks passed (${((Date.now() - started) / 1000).toFixed(0)} s)`
  : `check:web: ${failures} of ${checks} checks failed`);
process.exit(failures === 0 ? 0 : 1);
