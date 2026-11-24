// End-to-end checks of the web UI in real browsers, Chromium, Firefox and
// WebKit: the exact parts of the manual checklist (web/README.md,
// "Checking a change by hand"). For five settings, one for each kind of
// colors and one of the newer kernels, the downloaded PNG has the CLI's
// pixel values; for both
// machines, at their screens' sizes, the PNG too, and their files are the
// CLI's, byte for byte; the split shows the original left of it and the
// result right of it, exact to the screen pixel, dragging its handle
// selects nothing, and a click on "Original" or "Result" moves it to its
// end; the target's menu is disabled before a picture, takes the focus
// with the first and shows each choice; a run works with worker.js
// blocked once the page has loaded; the
// sample picture loads from both its links, says so when it can't be
// fetched, and its result has the CLI's pixels.
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
  // Under a curve (docs/gamma.md): the page's gamma segments, and "gray
  // first", which turns a picture gray by the curve.
  { what: '4 levels, Atkinson, sRGB', colors: 'levels', levels: '4', kernel: 'atkinson', gamma: 'srgb',
    cli: ['--levels', '4', '--kernel', 'atkinson', '--gamma', 'srgb'], name: 'levels4-atkinson-srgb' },
  { what: 'the CGA palette, Floyd-Steinberg, gray first, gamma 1.5', colors: 'cga16', kernel: 'floyd-steinberg', gamma: '1.5', gray: true,
    cli: ['--palette', 'cga16', '--kernel', 'floyd-steinberg', '--gamma', '1.5', '--gray'], name: 'cga16-floyd-steinberg-gamma1.5-gray' },
  // Serpentine scanning (decision 36): its switch, disabled until a
  // kernel is chosen, as the CLI rejects --serpentine with none.
  { what: '4 levels, Floyd-Steinberg, serpentine', colors: 'levels', levels: '4', kernel: 'floyd-steinberg', serpentine: true,
    cli: ['--levels', '4', '--kernel', 'floyd-steinberg', '--serpentine'], name: 'levels4-floyd-steinberg-serpentine' },
];
// The page's two switches, by their names.
const GRAY_SWITCH = { name: 'Turn the picture gray first' };
const SERPENTINE_SWITCH = { name: 'Serpentine: every other row right to left' };
// The page's three menus, by their names: since the target became one
// (decision 37), the colors' and the kernel's places among the selects
// have moved.
const TARGET_MENU = { name: 'Target' };
const COLORS_MENU = { name: 'Colors' };
const KERNEL_MENU = { name: 'Error diffusion' };
// What the target's menu shows for each target: its name, and its line,
// which also describes the select to screen readers.
const TARGETS = [
  { value: 'zx-spectrum', title: 'ZX Spectrum', line: '256 × 192, 2 colors per 8×8 cell' },
  { value: 'c64-hires', title: 'Commodore 64', line: '320 × 200, 2 colors per 8×8 cell' },
  { value: 'any', title: 'Any screen', line: 'any size, the colors you choose' },
];
// `dir` keeps each entry's CLI files apart; the names in it are the
// picture's, so that a tape's name is the page's.
const MACHINES = [
  { what: 'the ZX Spectrum, Bayer 8', picture: 'color-256x192', target: 'zx-spectrum', bayer: '8', formats: ['png', 'scr', 'tap'],
    dir: 'zx-spectrum', name: 'zx-spectrum-bayer8', cli: [] },
  { what: 'the C64, Bayer 8', picture: 'color-320x200', target: 'c64-hires', bayer: '8', formats: ['png', 'prg', 'art'],
    dir: 'c64-hires', name: 'c64-hires-bayer8', cli: [] },
  { what: 'the ZX Spectrum, Bayer 4, sRGB', picture: 'color-256x192', target: 'zx-spectrum', bayer: '4', gamma: 'srgb', formats: ['png', 'scr'],
    dir: 'zx-spectrum-srgb', name: 'zx-spectrum-bayer4-srgb', cli: ['--gamma', 'srgb'] },
];
const PICTURE = 'color-320x200';
// With a gamma, the page fits and flattens in the curve's light (linear
// light's decision 6, CLAUDE.md). The reference prepares the same
// picture in Node with the page's own compiled code (Puregrain.Web.Prepare),
// and the CLI dithers that: the page's results must be the CLI's. The
// transparent picture's channels are only 0 or 255, which come back exactly
// from a canvas too, should a browser here lack WebGL (web/CLAUDE.md,
// "Transparency"); black over white at every alpha still mixes in light.
const PREPARED = [
  { what: 'the 512x512 composite fitted to the ZX Spectrum, Bayer 4, sRGB', picture: 'color-512', target: 'zx-spectrum',
    fit: { width: 256, height: 192 }, bayer: '4', gamma: 'srgb', formats: ['png', 'scr'], name: 'zx-spectrum-fit-bayer4-srgb',
    cli: ['--machine', 'zx-spectrum', '--bayer', '4', '--gamma', 'srgb'] },
  { what: 'eight colors at every alpha on white, 4 levels, Atkinson, sRGB', picture: 'alpha-ramps',
    colors: 'levels', levels: '4', kernel: 'atkinson', gamma: 'srgb', formats: ['png'], name: 'levels4-atkinson-srgb',
    cli: ['--levels', '4', '--kernel', 'atkinson', '--gamma', 'srgb'] },
];

fs.rmSync(out, { recursive: true, force: true });
for (const dir of ['downloads', 'prepared', ...MACHINES.map((m) => m.dir)]) fs.mkdirSync(`${out}/${dir}`, { recursive: true });
for (const size of ['320x200', '256x192', '512', '2048x1024']) {
  execFileSync('node', ['scripts/generate-images.mjs', '--pattern', 'color', '--size', size, '--out', out]);
}
{
  // Eight colors of 0s and 255s, a band of 8 rows each, at alpha 0 to 255
  // from left to right.
  const png = new PNG({ width: 256, height: 64 });
  for (let y = 0; y < 64; y++) {
    for (let x = 0; x < 256; x++) {
      const c = y >> 3;
      png.data.set([c & 4 ? 255 : 0, c & 2 ? 255 : 0, c & 1 ? 255 : 0, x], (y * 256 + x) * 4);
    }
  }
  fs.writeFileSync(`${out}/alpha-ramps.png`, PNG.sync.write(png, { colorType: 6 }));
}
{
  // Every value at every alpha (v2's phase 2): red down the rows, alpha
  // across, green and blue other orders of the values.
  const png = new PNG({ width: 256, height: 256 });
  for (let y = 0; y < 256; y++) for (let x = 0; x < 256; x++) png.data.set([y, 255 - y, (y * 37) % 256, x], (y * 256 + x) * 4);
  fs.writeFileSync(`${out}/every-alpha.png`, PNG.sync.write(png, { colorType: 6 }));
}
const cli = (input, output, options) => execFileSync('node', ['cli/bin/puregrain-cli.mjs', input, output, ...options]);
for (const s of SETTINGS) cli(`${out}/${PICTURE}.png`, `${out}/cli-${s.name}.png`, s.cli);
// The sample picture (decision 35), the repository's file, which the build
// copies next to the page: a photo, dithered under the gamma that looks
// closest at 100% with this palette (pictures/README.md).
const SAMPLE = { file: 'pictures/macaw-and-toucan.png', name: 'macaw-and-toucan.png',
  download: 'macaw-and-toucan-cga16-floyd-steinberg-gamma1.8.png' };
cli(SAMPLE.file, `${out}/cli-sample.png`, ['--palette', 'cga16', '--kernel', 'floyd-steinberg', '--gamma', '1.8']);
// The tape's name comes from the output file's name: the picture's, as on the page.
{
  const Prepare = await import(path.resolve('output/Puregrain.Web.Prepare/index.js'));
  const Settings = await import(path.resolve('output/Puregrain.Web.Settings/index.js'));
  const gammas = { srgb: Settings.GammaSrgb.value, off: Settings.GammaOff.value };
  for (const p of PREPARED) {
    const picture = PNG.sync.read(fs.readFileSync(`${out}/${p.picture}.png`));
    const pixels = new Uint8ClampedArray(picture.data);
    const size = { width: picture.width, height: picture.height };
    const tables = Prepare.lightTables(gammas[p.gamma]);
    const prepared = p.fit
      ? { ...p.fit, pixels: Prepare.fitOnto(tables)(pixels)(size)(p.fit)(Prepare.white)() }
      : { ...size, pixels: Prepare.flatten(tables)(pixels)(Prepare.white)() };
    const png = new PNG({ width: prepared.width, height: prepared.height });
    png.data = Buffer.from(prepared.pixels);
    fs.writeFileSync(`${out}/prepared/${p.picture}.png`, PNG.sync.write(png, { colorType: 2 }));
    for (const format of p.formats) cli(`${out}/prepared/${p.picture}.png`, `${out}/prepared/${p.picture}-dithered.${format}`, p.cli);
  }
  // The file's own values flattened onto white, in Node, with off and srgb:
  // what the page must show as the original.
  const every = PNG.sync.read(fs.readFileSync(`${out}/every-alpha.png`));
  for (const gamma of ['off', 'srgb']) {
    const flat = Prepare.flatten(Prepare.lightTables(gammas[gamma]))(new Uint8ClampedArray(every.data))(Prepare.white)();
    fs.writeFileSync(`${out}/prepared/every-alpha-${gamma}.rgba`, Buffer.from(flat));
  }
}
for (const m of MACHINES) {
  for (const format of m.formats) {
    cli(`${out}/${m.picture}.png`, `${out}/${m.dir}/${m.picture}.${format}`, ['--machine', m.target, '--bayer', m.bayer, ...m.cli]);
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
  const targetMenu = page.getByRole('combobox', TARGET_MENU);
  const colorsMenu = page.getByRole('combobox', COLORS_MENU);
  const kernelMenu = page.getByRole('combobox', KERNEL_MENU);
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
  // The segments are radio buttons; one is picked once it's available.
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
      await colorsMenu.selectOption('levels');
      await page.locator('.stepper input[type=number]').fill('4');
      await kernelMenu.selectOption('atkinson');
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

  // The engine check (v2.3): this engine passes it, and
  // the icon left of Help says so, opens its sentence with a link to the
  // README's section, and Escape closes it, the focus back on the icon.
  {
    await page.goto(pageUrl);
    await page.waitForFunction(() => ['passed', 'failed', 'not-run'].includes(document.documentElement.dataset.engineCheck), null, { timeout: 30000 });
    const state = await page.evaluate(() => document.documentElement.dataset.engineCheck);
    const button = page.locator('.top .engine-button');
    const name = (await button.textContent()).trim();
    await button.click();
    const box = page.locator('.top .engine-box');
    const shown = await box.isVisible();
    const sentence = shown ? (await box.locator('p').textContent()).trim() : '';
    const link = await box.locator('a').getAttribute('href');
    await page.keyboard.press('Escape');
    const closed = await box.isHidden();
    const focused = await page.evaluate(() => document.activeElement?.classList.contains('engine-button') ?? false);
    // Opened again, a click elsewhere on the page closes it too.
    await button.click();
    const reopened = await box.isVisible();
    await page.mouse.click(20, 400);
    const clickedAway = await box.isHidden();
    report(state === 'passed' && name === 'Engine check: passed' && shown && sentence.startsWith('Engine check passed:')
      && link.endsWith('/web/README.md#the-engine-check') && closed && focused && reopened && clickedAway,
      `${engine}: the engine check ${state}; its icon, "${name}", opens "${sentence}" with a link to Help${closed && focused ? ', and Escape closes it, the focus back on the icon' : ', but Escape doesn\'t close it, or the focus is lost'}${reopened && clickedAway ? ', as does a click elsewhere' : ', but a click elsewhere doesn\'t close it'}`);
  }

  // The target, a menu that looks like its card (decision 37): disabled
  // before a picture, it takes the focus with the first one; after each
  // choice, its face shows the chosen target's name and line, and the
  // line describes the select (the face itself is hidden from screen
  // readers).
  {
    await page.goto(pageUrl);
    const disabledFirst = await targetMenu.isDisabled();
    await page.locator('input[type=file]').first().setInputFiles(`${out}/${PICTURE}.png`);
    const focused = await page.waitForFunction(() => document.activeElement?.matches('.card-menu select') ?? false, null, { timeout: 5000 })
      .then(() => true, () => false);
    const wrong = [];
    for (const t of TARGETS) {
      await targetMenu.selectOption(t.value);
      const shows = await page.waitForFunction((want) => {
        const select = document.querySelector('.card-menu select');
        const face = document.querySelector('.card-menu .face');
        const description = document.getElementById(select?.getAttribute('aria-describedby') ?? '')?.textContent;
        return select?.value === want.value && face?.querySelector('b')?.textContent === want.title
          && face?.querySelector('small')?.textContent === want.line && description === want.line;
      }, t, { timeout: 5000 }).then(() => true, () => false);
      if (!shows) {
        const now = await page.evaluate(() => {
          const select = document.querySelector('.card-menu select');
          const description = document.getElementById(select?.getAttribute('aria-describedby') ?? '')?.textContent;
          return `${select?.value} shows "${document.querySelector('.card-menu .face b')?.textContent}", ` +
            `"${document.querySelector('.card-menu .face small')?.textContent}", described as "${description}"`;
        });
        wrong.push(`${t.value}: ${now}`);
      }
    }
    report(disabledFirst && focused && wrong.length === 0,
      `${engine}: the target's menu is ${disabledFirst ? 'disabled' : 'NOT disabled'} before a picture and ${focused ? 'takes' : "DOESN'T take"} the focus with the first; ` +
      (wrong.length === 0
        ? `its face and description follow the choice (${TARGETS.map((t) => t.title).join(', ')})`
        : `its face or description doesn't follow the choice: ${wrong.join('; ')}`));
  }

  // Pasting (v2.6). Ctrl+V as the browser sends it, a paste event: a
  // picture loads, named pasted.png, and dithers to the CLI's pixels; a
  // paste with no picture says so, one into a number field stays the
  // field's. The drop zone's line names the key, ⌘V on a Mac (a page told
  // it's one). Firefox empties the clipboard of a paste event a page
  // sends, and headless, its own clipboard holds no pictures (a picture
  // written to it pasted none), so there the picture's part is left to the
  // manual checklist. In Chromium, which lets the check allow reading the
  // clipboard, "paste" reads it: a picture loads, none says so; Firefox
  // and WebKit ask the user, so a note says it's left to the checklist.
  {
    const b64 = fs.readFileSync(`${out}/${PICTURE}.png`).toString('base64');
    const pasteEvent = (args) => page.evaluate(({ picture, text, into }) => {
      const data = new DataTransfer();
      if (picture !== null) data.items.add(new File([Uint8Array.from(atob(picture), (c) => c.charCodeAt(0))], 'image.png', { type: 'image/png' }));
      if (text !== null) data.setData('text/plain', text);
      const target = into === null ? document.body : document.querySelector(into);
      target.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
    }, args);
    const named = (name) => page.waitForFunction((n) => document.querySelector('.picture-name')?.textContent === n, name, { timeout: 10000 })
      .then(() => true, () => false);
    const barNote = () => page.evaluate(() => {
      const box = document.querySelector('.bar-file');
      return box === null || box.hidden ? null : box.textContent.trim();
    });
    const nothing = "There's no picture on the clipboard: copy one first, with \"Copy image\" on a web page, or take a screenshot.";

    await page.goto(pageUrl);
    const line = (await page.locator('.drop-paste').textContent()).trim();
    const pictureChecked = engine !== 'Firefox';
    let loaded = false;
    let file = { name: '(none)' };
    let diff = 'not run';
    if (pictureChecked) {
      const before = await runs();
      await pasteEvent({ picture: b64, text: null, into: null });
      loaded = await named('pasted.png');
      if (loaded) {
        await colorsMenu.selectOption('levels');
        await page.locator('.stepper input[type=number]').fill('4');
        await kernelMenu.selectOption('atkinson');
        await finished(before);
        file = await download(() => page.locator('.downloads button').first().click());
        diff = differing(pixelsOf(file.bytes), pixelsOf(fs.readFileSync(`${out}/cli-levels4-atkinson.png`)));
      }
    } else {
      console.log(`NOTE  ${engine}: a pasted picture isn't checked here: Firefox empties a page's own paste event, and its headless clipboard holds no pictures; it's on the manual checklist`);
    }
    // Without a pasted picture, one opened, for the levels' field.
    if (!loaded) {
      await open(PICTURE);
      await colorsMenu.selectOption('levels');
    }
    await pasteEvent({ picture: null, text: '7', into: '.stepper input[type=number]' });
    await sleep(300);
    const fieldQuiet = (await barNote()) === null;
    await pasteEvent({ picture: null, text: 'hello', into: null });
    await sleep(300);
    const saysNothing = (await barNote()) === nothing;
    const macPage = await page.context().newPage();
    await macPage.addInitScript(() => Object.defineProperty(Navigator.prototype, 'platform', { get: () => 'MacIntel' }));
    await macPage.goto(pageUrl);
    const macLine = (await macPage.locator('.drop-paste').textContent()).trim();
    await macPage.close();
    const expected = 'pasted-levels4-atkinson.png';
    const pictureOk = !pictureChecked || (loaded && file.name === expected && diff === 0);
    report(line === 'or paste one (Ctrl+V)' && macLine === 'or paste one (⌘V)' && pictureOk && fieldQuiet && saysNothing,
      `${engine}: pasting: the drop zone says "${line}", on a Mac "${macLine}"; ` +
      (pictureChecked
        ? `a pasted picture ${loaded ? 'loads as pasted.png' : "DOESN'T load as pasted.png"}, ` +
          `${file.name}${file.name === expected ? '' : ` (not ${expected})`}, ${diff === 0 ? "the CLI's pixels" : typeof diff === 'number' ? `${diff} pixels differ from the CLI's` : diff}; `
        : 'the pasted picture not checked here (see the note); ') +
      `a paste into a number field ${fieldQuiet ? 'stays the field\'s' : 'gives a note'}, one with no picture ${saysNothing ? 'says so' : "DOESN'T say so"}`);

    if (engine === 'Chromium') {
      await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: pageUrl });
      await page.goto(pageUrl);
      await page.evaluate(async (picture) => {
        const bytes = Uint8Array.from(atob(picture), (c) => c.charCodeAt(0));
        await navigator.clipboard.write([new ClipboardItem({ 'image/png': new Blob([bytes], { type: 'image/png' }) })]);
      }, b64);
      await page.locator('.drop-paste .link').click();
      const fromLink = await named('pasted.png');
      await page.evaluate(() => navigator.clipboard.writeText('hello'));
      await page.locator('.steps .hint .link.main').click();
      await sleep(500);
      const linkSaysNothing = (await barNote()) === nothing;
      await page.context().clearPermissions();
      report(fromLink && linkSaysNothing,
        `${engine}: "paste" reads the clipboard: a picture ${fromLink ? 'loads as pasted.png' : "DOESN'T load"}, and with none ${linkSaysNothing ? 'it says so' : "it DOESN'T say so"}`);
    } else {
      console.log(`NOTE  ${engine}: "paste" (reading the clipboard) isn't checked here: the browser asks the user first; it's on the manual checklist`);
    }
  }

  // Addresses (v2.6): a drop without a file, as a picture or a link from
  // another page brings, has an address, which the page fetches. The
  // page's own server serves the sample picture; the same server as
  // 127.0.0.1 is another site, which doesn't let other pages read its
  // pictures. A drag holding an address lights the drop zone; a refused
  // address says so; a picture inside a link loads by its own address,
  // exactly the file (the CLI's pixels after dithering), named after it.
  // A pasted address loads the same way where the check's paste event
  // keeps its text (not in Firefox, see "Pasting").
  {
    const here = `${pageUrl}${SAMPLE.file}`;
    const elsewhere = here.replace('localhost', '127.0.0.1');
    const dragEvent = (type, data) => page.evaluate(({ type, data }) => {
      const transfer = new DataTransfer();
      for (const [kind, value] of Object.entries(data)) transfer.setData(kind, value);
      document.querySelector('.drop').dispatchEvent(new DragEvent(type, { dataTransfer: transfer, bubbles: true, cancelable: true }));
    }, { type, data });
    const startNote = () => page.evaluate(() => document.querySelector('.start-note')?.textContent.trim() ?? '');
    const refused = "The picture couldn't be fetched from 127.0.0.1:8080: the site doesn't let other pages read its pictures, or can't be reached. Copy the picture itself and paste it instead.";

    await page.goto(pageUrl);
    await dragEvent('dragenter', { 'text/uri-list': here });
    const lit = await page.locator('.drop.lit').count() === 1;
    await dragEvent('drop', { 'text/uri-list': elsewhere });
    const saysRefused = await page.waitForFunction((text) => document.querySelector('.start-note')?.textContent.trim() === text, refused, { timeout: 10000 })
      .then(() => true, async () => { console.log(`   (the empty page says: ${await startNote()})`); return false; });
    const before = await runs();
    await dragEvent('drop', { 'text/uri-list': `${pageUrl}elsewhere.html`, 'text/html': `<a href="${pageUrl}elsewhere.html"><img alt="birds" src="${here}"></a>` });
    const loaded = await page.waitForFunction((name) => document.querySelector('.picture-name')?.textContent === name, SAMPLE.name, { timeout: 15000 })
      .then(() => true, () => false);
    let file = { name: '(none)' };
    let diff = 'not run';
    if (loaded) {
      await colorsMenu.selectOption('cga16');
      await kernelMenu.selectOption('floyd-steinberg');
      await pick('gamma', '1.8');
      await finished(before);
      file = await download(() => page.locator('.downloads button').first().click());
      diff = differing(pixelsOf(file.bytes), pixelsOf(fs.readFileSync(`${out}/cli-sample.png`)));
    }
    let pasted = 'not checked here';
    if (engine !== 'Firefox') {
      await page.evaluate((address) => {
        const data = new DataTransfer();
        data.setData('text/plain', address);
        document.body.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data, bubbles: true, cancelable: true }));
      }, `${pageUrl}logo/zx/lockup.png`);
      pasted = await page.waitForFunction(() => document.querySelector('.picture-name')?.textContent === 'lockup.png', null, { timeout: 15000 })
        .then(() => 'loads lockup.png', () => "DOESN'T load lockup.png");
    }
    report(lit && saysRefused && loaded && file.name === SAMPLE.download && diff === 0 && pasted !== "DOESN'T load lockup.png",
      `${engine}: addresses: a drag holding one ${lit ? 'lights' : "DOESN'T light"} the drop zone; one from a site that refuses ${saysRefused ? 'says so' : "DOESN'T say so"}; ` +
      `a picture in a link ${loaded ? 'loads by its own address' : "DOESN'T load"}, ${file.name}${file.name === SAMPLE.download ? '' : ` (not ${SAMPLE.download})`}, ` +
      `${diff === 0 ? "the CLI's pixels" : typeof diff === 'number' ? `${diff} pixels differ from the CLI's` : diff}; a pasted address: ${pasted}`);
  }

  // The theme switch: a toggle named "Dark theme", pressed or not, whose
  // tooltip says what a click does, "Switch to the dark theme" or "…light
  // theme"; the name stays the same.
  {
    await page.goto(pageUrl);
    const button = page.locator('.top .theme');
    const read = () => button.evaluate((b) => ({ pressed: b.getAttribute('aria-pressed'), title: b.title, name: b.textContent.trim() }));
    const states = [await read()];
    await button.click();
    states.push(await read());
    await button.click();
    states.push(await read());
    const right = (s) => s.name === 'Dark theme'
      && s.title === (s.pressed === 'true' ? 'Switch to the light theme' : 'Switch to the dark theme');
    report(states.every(right) && states[0].pressed !== states[1].pressed && states[1].pressed !== states[2].pressed,
      `${engine}: the theme switch, toggled twice: ${states.map((s) => `pressed ${s.pressed}, "${s.title}"`).join('; ')}; named "${states[0].name}"`);
  }

  // A long run, on 2 megapixels (2026-11-15): its progress shows at once,
  // and the picture's frame is marked as working while it goes. A gamma
  // changed after it, on this opaque picture, keeps the result before on
  // show during the next run (not the original); Escape cancels, and the
  // mark goes.
  {
    await open('color-2048x1024');
    let before = await runs();
    const t0 = Date.now();
    await kernelMenu.selectOption('floyd-steinberg');
    const progressAt = await page.waitForFunction(() => document.querySelector('.progress:not([hidden])') !== null, null, { timeout: 5000 })
      .then(() => Date.now() - t0, () => null);
    const working = await page.locator('.layers.working').count() === 1;
    await finished(before);
    const doneUnmarked = await page.locator('.layers.working').count() === 0;
    before = await runs();
    await pick('gamma', 'srgb');
    await page.waitForFunction((n) => window.__runs.length > n, before);
    const keptResult = await page.evaluate(() => document.querySelector('canvas.result')?.hidden === false && document.querySelector('.layers.working') !== null);
    await page.keyboard.press('Escape');
    const cancelledUnmarked = await page.waitForFunction(() => document.querySelector('.layers.working') === null, null, { timeout: 5000 }).then(() => true, () => false);
    report(progressAt !== null && progressAt < 700 && working && doneUnmarked && keptResult && cancelledUnmarked,
      `${engine}: on 2 megapixels, a run's progress shows at once (${progressAt} ms) and its frame is marked while it goes${doneUnmarked ? '' : ' (still marked when done)'}; ` +
      `a new gamma keeps the result before on show${keptResult ? '' : ' (NOT: the original shows)'}; Escape cancels${cancelledUnmarked ? '' : ' (the mark stays)'}`);
  }

  // Under the gamma, a note while it can't change the picture: after
  // loading (no colors, no method), and gone once a kernel dithers.
  {
    await open(PICTURE);
    const note = page.locator('.note', { hasText: 'Gamma changes the picture only' });
    const shown = await note.isVisible();
    await kernelMenu.selectOption('floyd-steinberg');
    await page.waitForFunction(() => ![...document.querySelectorAll('.note')].some((n) => n.textContent.startsWith('Gamma changes')), null, { timeout: 5000 }).catch(() => {});
    const gone = await note.count() === 0;
    report(shown && gone, `${engine}: the note under the gamma ${shown ? 'shows after loading' : "doesn't show after loading"} and ${gone ? 'goes once a kernel dithers' : 'stays with a kernel'}`);
  }

  // The sample picture (decision 35), offered before the first picture in
  // the drop zone and in step 1's hint: blocked, the empty page says it
  // couldn't be loaded; from either link it loads; dithered, its download
  // has the CLI's pixels for the repository's file.
  {
    const loaded = () => page.waitForFunction((name) => document.querySelector('.picture-name')?.textContent === name, SAMPLE.name, { timeout: 30000 })
      .then(() => true, () => false);
    await page.goto(pageUrl);
    await page.context().route(`**/pictures/${SAMPLE.name}`, (route) => route.abort());
    let blockedSays = false;
    try {
      await page.locator('.drop .sample button.link').click();
      blockedSays = await page.locator('.start-note .warning', { hasText: "The sample picture couldn't be loaded." })
        .waitFor({ timeout: 5000 }).then(() => true, () => false);
    } finally {
      await page.context().unroute(`**/pictures/${SAMPLE.name}`);
    }
    await page.goto(pageUrl);
    await page.locator('.steps .hint button.link', { hasText: 'try the sample picture' }).click();
    const fromStep1 = await loaded();
    await page.goto(pageUrl);
    await page.locator('.drop .sample button.link').click();
    const fromZone = await loaded();
    let file = { name: '(none)' };
    let diff = 'not run';
    if (fromZone) {
      const before = await runs();
      await colorsMenu.selectOption('cga16');
      await kernelMenu.selectOption('floyd-steinberg');
      await pick('gamma', '1.8');
      await finished(before);
      file = await download(() => page.locator('.downloads button').first().click());
      diff = differing(pixelsOf(file.bytes), pixelsOf(fs.readFileSync(`${out}/cli-sample.png`)));
    }
    report(blockedSays && fromStep1 && fromZone && file.name === SAMPLE.download && diff === 0,
      `${engine}: the sample picture: blocked, the empty page ${blockedSays ? 'says so' : "DOESN'T say so"}; ` +
      `it loads from step 1's hint${fromStep1 ? '' : ' (NOT)'} and from the drop zone${fromZone ? '' : ' (NOT)'}; ` +
      `the IBM PC colors, Floyd-Steinberg, gamma 1.8: ${file.name}${file.name === SAMPLE.download ? '' : ` (not ${SAMPLE.download})`}, ` +
      `${diff === 0 ? "the CLI's pixels" : typeof diff === 'number' ? `${diff} pixels differ from the CLI's` : diff}`);
  }

  for (const s of SETTINGS) {
    await open(PICTURE);
    const before = await runs();
    await colorsMenu.selectOption(s.colors);
    if (s.levels) await page.locator('.stepper input[type=number]').fill(s.levels);
    // With colors but no kernel yet, serpentine scanning can't act.
    const serpentineFirst = s.serpentine ? await page.getByRole('switch', SERPENTINE_SWITCH).isDisabled() : true;
    if (s.kernel) await kernelMenu.selectOption(s.kernel);
    if (s.serpentine) await page.getByRole('switch', SERPENTINE_SWITCH).evaluate((toggle) => toggle.click());
    if (s.bayer) await pick('bayer', s.bayer);
    if (s.gamma) await pick('gamma', s.gamma);
    if (s.gray) await page.getByRole('switch', GRAY_SWITCH).evaluate((toggle) => toggle.click());
    await finished(before);
    const expected = `${PICTURE}-${s.name}.png`;
    const file = await download(() => page.locator('.downloads button').first().click());
    const diff = differing(pixelsOf(file.bytes), pixelsOf(fs.readFileSync(`${out}/cli-${s.name}.png`)));
    report(file.name === expected && diff === 0 && serpentineFirst,
      `${engine}: ${s.what}: ${file.name}${file.name === expected ? '' : ` (not ${expected})`}, ${diff === 0 ? "the CLI's pixels" : `${diff} pixels differ from the CLI's`}` +
      (s.serpentine ? `; its switch ${serpentineFirst ? 'disabled' : 'NOT disabled'} until a kernel` : ''));
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
    await targetMenu.selectOption(m.target);
    await pick('bayer', m.bayer);
    if (m.gamma) await pick('gamma', m.gamma);
    await finished(before);
    for (const format of m.formats) {
      const expected = `${m.picture}-${m.name}.${format}`;
      const file = await download(fromList(format));
      const reference = fs.readFileSync(`${out}/${m.dir}/${m.picture}.${format}`);
      const diff = format === 'png' ? differing(pixelsOf(file.bytes), pixelsOf(reference)) : null;
      const same = format === 'png' ? diff === 0 : file.bytes.equals(reference);
      const how = format === 'png'
        ? (diff === 0 ? "the CLI's pixels" : `${diff} pixels differ from the CLI's`)
        : (same ? "the CLI's file, byte for byte" : `not the CLI's file (${file.bytes.length} bytes, the CLI's ${reference.length})`);
      report(file.name === expected && same, `${engine}: ${m.what}: ${file.name}${file.name === expected ? '' : ` (not ${expected})`}, ${how}`);
    }
  }

  for (const p of PREPARED) {
    await open(p.picture);
    const before = await runs();
    if (p.target) await targetMenu.selectOption(p.target);
    if (p.fit) await page.locator('label.check input[type=checkbox]').setChecked(true);
    if (p.colors) await colorsMenu.selectOption(p.colors);
    if (p.levels) await page.locator('.stepper input[type=number]').fill(p.levels);
    if (p.kernel) await kernelMenu.selectOption(p.kernel);
    if (p.bayer) await pick('bayer', p.bayer);
    await pick('gamma', p.gamma);
    await finished(before);
    for (const format of p.formats) {
      const expected = `${p.picture}-${p.name}.${format}`;
      const file = await download(p.target ? fromList(format) : () => page.locator('.downloads button').first().click());
      const reference = fs.readFileSync(`${out}/prepared/${p.picture}-dithered.${format}`);
      const diff = format === 'png' ? differing(pixelsOf(file.bytes), pixelsOf(reference)) : null;
      const same = format === 'png' ? diff === 0 : file.bytes.equals(reference);
      const how = format === 'png'
        ? (diff === 0 ? "the CLI's pixels on the picture prepared in Node" : `${diff} pixels differ from the CLI's on the picture prepared in Node`)
        : (same ? "the CLI's file, byte for byte" : `not the CLI's file (${file.bytes.length} bytes, the CLI's ${reference.length})`);
      report(file.name === expected && same, `${engine}: ${p.what}: ${file.name}${file.name === expected ? '' : ` (not ${expected})`}, ${how}`);
    }
  }

  // A picture with transparency is read exactly, through an <img> and
  // WebGL (see Puregrain.Web.Picture): the original the page shows, put onto
  // white with off and with srgb, is the file's own values put onto white in
  // Node. Without WebGL, the page reads the canvas's rounded values, by
  // design not exact: then the line says so instead of failing.
  {
    // The original as drawn, read in the page: whether it's drawn (opaque),
    // a hash of its bytes, to see it drawn again, and how many values
    // differ from the expected ones when they're given (sent once, at the
    // end, rather than the canvas copied out at every look).
    const shown = (b64) => page.evaluate((expected) => {
      const c = document.querySelector('canvas.picture:not(.result)');
      const got = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
      const want = expected === null ? null : Uint8Array.from(atob(expected), (ch) => ch.charCodeAt(0));
      let hash = 0;
      let differ = 0;
      for (let i = 0; i < got.length; i++) {
        hash = (hash * 31 + got[i]) >>> 0;
        if (want !== null && got[i] !== want[i]) differ++;
      }
      return { drawn: got[3] === 255, hash, differ };
    }, b64);
    const webgl = await page.evaluate(() => document.createElement('canvas').getContext('webgl') !== null);
    await open('every-alpha');
    const results = [];
    let before = null;
    for (const gamma of ['off', 'srgb']) {
      if (gamma !== 'off') await pick('gamma', gamma);
      // Drawn, and with another gamma drawn again: until then, or 5 s.
      let now = await shown(null);
      for (let waited = 0; waited < 5000 && (!now.drawn || now.hash === before); waited += 100) {
        await sleep(100);
        now = await shown(null);
      }
      before = now.hash;
      const { differ } = await shown(fs.readFileSync(`${out}/prepared/every-alpha-${gamma}.rgba`).toString('base64'));
      results.push(`${gamma} ${differ === 0 ? 'exact' : `${differ} values off`}`);
    }
    const exact = results.every((r) => r.endsWith('exact'));
    if (webgl || exact) {
      report(exact, `${engine}: every value at every alpha, put onto white: the shown original is the file's values put onto white in Node (${results.join(', ')})`);
    } else {
      console.log(`NOTE  ${engine}: no WebGL here, so a picture with transparency is read from the canvas, rounded by design (${results.join(', ')})`);
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
