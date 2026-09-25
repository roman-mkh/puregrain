// Benchmarks the dithering pipeline through the real CLI, timing only the
// dithering itself: the CLI's "Dithered in X ms" line, which excludes PNG
// decoding/encoding, gray conversion and Node startup.
//
// Every configuration runs several times, each in a fresh process (how the
// CLI is really used, JIT warm-up included), and the median is reported.
// Runs are interleaved — round 1 of every configuration, then round 2, ... —
// so slow drift during a long run (heat, background load) spreads over all
// configurations instead of landing on whichever ran last.
//
// Output: markdown tables on stdout, ready for docs/benchmarks-dithering.md;
// progress on stderr; all raw run times as JSON with --json (the input for
// scripts/plot-benchmarks.mjs). Build first: npm run build.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');
const cli = path.join(root, 'cli', 'bin', 'puregrain-cli.mjs');
const generator = path.join(root, 'scripts', 'generate-images.mjs');
const benchDir = path.join(root, 'samples', 'bench');

// Quantizer modes, all with Floyd–Steinberg. RGB levels use 6 rather than
// 4 so they compare directly with websafe216: the two produce
// byte-identical output (docs/test-images.md, "Exact checks").
const MODES = [
  { id: 'threshold', label: 'threshold 128', image: 'gray', args: ['--threshold', '128'] },
  { id: 'levels-gray', label: 'levels 4 (gray)', image: 'gray', args: ['--levels', '4'] },
  { id: 'levels-rgb', label: 'levels 6 (RGB)', image: 'color', args: ['--levels', '6'] },
  { id: 'websafe216', label: 'websafe216', image: 'color', args: ['--palette', 'websafe216'] },
  { id: 'bw', label: 'bw', image: 'color', args: ['--palette', 'bw'] },
];

// Kernels, all with the default 1-bit threshold on the gray composite.
const KERNELS = ['floyd-steinberg', 'atkinson', 'jjn'];

const USAGE = `Usage: node scripts/benchmark.mjs [options]

  --runs <n>      runs per configuration; the median is reported (default: 5)
  --sizes <list>  square image sides, comma-separated (default: 64,128,256,512,1024)
  --suite <s>     modes, kernels or all (default: all)
  --json <file>   also write every run's time, and the environment, as JSON
  --report <file> don't measure: print the tables for a JSON file written by --json`;

function fail(message) {
  console.error(`${message}\n\n${USAGE}`);
  process.exit(1);
}

const run = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8' }).trim();
const tryRun = (cmd, args) => { try { return run(cmd, args); } catch { return 'unknown'; } };

function environment() {
  const cpus = os.cpus();
  const dirty = tryRun('git', ['-C', root, 'status', '--porcelain']) !== '';
  return {
    date: new Date().toISOString().slice(0, 10),
    node: process.version,
    cpu: `${cpus[0]?.model ?? 'unknown'} (${cpus.length} logical cores)`,
    os: `${os.type()} ${os.release()} (${os.arch()})`,
    memory: `${Math.round(os.totalmem() / 2 ** 30)} GiB`,
    purs: tryRun(path.join(root, 'node_modules', '.bin', 'purs'), ['--version']),
    spago: tryRun(path.join(root, 'node_modules', '.bin', 'spago'), ['--version']),
    commit: tryRun('git', ['-C', root, 'rev-parse', '--short', 'HEAD']) + (dirty ? ' (+ uncommitted changes)' : ''),
  };
}

// The configurations to measure. The kernel suite's Floyd–Steinberg row is
// the modes suite's threshold row, so that configuration is measured once.
function configurations(suite, sizes) {
  const byKey = new Map();
  const add = (size, kernel, mode) => {
    const key = `${size}-${kernel}-${mode.id}`;
    if (!byKey.has(key)) byKey.set(key, { key, size, kernel, mode, times: [] });
  };
  for (const size of sizes) {
    if (suite !== 'kernels') for (const mode of MODES) add(size, 'floyd-steinberg', mode);
    if (suite !== 'modes') for (const kernel of KERNELS) add(size, kernel, MODES[0]);
  }
  return [...byKey.values()];
}

function ditherOnce(config) {
  const input = path.join(benchDir, `${config.mode.image}-${config.size}.png`);
  const output = path.join(benchDir, `out-${config.key}.png`);
  const stdout = run(process.execPath, [cli, input, output, '--kernel', config.kernel, ...config.mode.args]);
  const match = /Dithered in ([0-9.]+) ms/.exec(stdout);
  if (!match) throw new Error(`No timing in the CLI output for ${config.key}:\n${stdout}`);
  return Number(match[1]);
}

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 === 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
};
const spread = (xs) => (Math.max(...xs) - Math.min(...xs)) / median(xs);
const ms = (x) => (x < 100 ? x.toFixed(1) : Math.round(x).toLocaleString('en-US'));
const minutes = (msTotal) => `${Math.round(msTotal / 60000)} min`;

function table(header, rows) {
  const line = (cells) => `| ${cells.join(' | ')} |`;
  return [line(header), line(header.map((h, i) => (i === 0 ? '---:' : '---:'))), ...rows.map(line)].join('\n');
}

function report(env, configs, sizes, runs, suite) {
  const find = (size, kernel, modeId) => configs.find((c) => c.size === size && c.kernel === kernel && c.mode.id === modeId);
  // Growth per doubling of the side over the three largest sizes (a
  // geometric mean over two steps): a single step can be off by one noisy
  // median, and the smallest sizes are dominated by the fixed cold start.
  const upper = sizes.slice(-3);
  const perDoubling = (kernel, modeId) =>
    (find(upper[upper.length - 1], kernel, modeId).median / find(upper[0], kernel, modeId).median) ** (1 / (upper.length - 1));
  const upperLabel = `${upper[0]}²→${upper[upper.length - 1]}²`;
  const out = [];
  out.push('**Environment:**', '');
  out.push(`- Date: ${env.date}; commit ${env.commit}`);
  out.push(`- CPU: ${env.cpu}; memory: ${env.memory}`);
  out.push(`- OS: ${env.os}`);
  out.push(`- Node ${env.node}; purs ${env.purs}; spago ${env.spago}`);
  out.push(`- ${runs} runs per configuration, interleaved; median reported`);
  out.push('');

  if (suite !== 'kernels') {
    out.push('**Quantizer modes** (Floyd–Steinberg; median ms, ×growth vs. the previous size):', '');
    const rows = sizes.map((size, i) => [
      `${size}`,
      (size * size).toLocaleString('en-US'),
      ...MODES.map((m) => {
        const now = find(size, 'floyd-steinberg', m.id).median;
        const prev = i > 0 ? find(sizes[i - 1], 'floyd-steinberg', m.id).median : null;
        return prev ? `${ms(now)} (×${(now / prev).toFixed(2)})` : ms(now);
      }),
    ]);
    if (upper.length >= 2) {
      rows.push([`per doubling, ${upperLabel}`, '', ...MODES.map((m) => `×${perDoubling('floyd-steinberg', m.id).toFixed(2)}`)]);
    }
    out.push(table(['Side N', 'Pixels', ...MODES.map((m) => m.label)], rows), '');
    const big = sizes[sizes.length - 1];
    const base = find(big, 'floyd-steinberg', 'threshold').median;
    out.push(`**Cost relative to threshold 128, at ${big}²:** ` +
      MODES.slice(1).map((m) => `${m.label} ×${(find(big, 'floyd-steinberg', m.id).median / base).toFixed(2)}`).join('; ') +
      `. websafe216 ÷ levels 6 (RGB), identical output: ×${(find(big, 'floyd-steinberg', 'websafe216').median / find(big, 'floyd-steinberg', 'levels-rgb').median).toFixed(2)}.`, '');
  }

  if (suite !== 'modes') {
    out.push('**Kernels** (threshold 128, gray; median ms):', '');
    const rows = sizes.map((size) => {
      const fs = find(size, 'floyd-steinberg', 'threshold').median;
      const at = find(size, 'atkinson', 'threshold').median;
      const jj = find(size, 'jjn', 'threshold').median;
      return [`${size}`, ms(fs), ms(at), ms(jj), `×${(at / fs).toFixed(2)}`, `×${(jj / fs).toFixed(2)}`];
    });
    if (upper.length >= 2) {
      rows.push([`per doubling, ${upperLabel}`, ...KERNELS.map((k) => `×${perDoubling(k, 'threshold').toFixed(2)}`), '', '']);
    }
    out.push(table(['Side N', 'floyd-steinberg', 'atkinson', 'jjn', 'atkinson ÷ FS', 'jjn ÷ FS'], rows), '');
  }

  // Spread for the large sizes separately: at the small ones a ~0.1 s
  // timing is mostly cold start, which says little about the dithering.
  const spreadLine = (cs) => {
    const s = cs.map((c) => ({ key: c.key, s: spread(c.times) })).sort((a, b) => a.s - b.s);
    return `median ${(median(s.map((x) => x.s)) * 100).toFixed(0)}%, largest ${(s[s.length - 1].s * 100).toFixed(0)}% (${s[s.length - 1].key})`;
  };
  out.push(`**Run-to-run spread** ((max − min) ÷ median): ${upperLabel}: ${spreadLine(configs.filter((c) => upper.includes(c.size)))}; ` +
    `all sizes: ${spreadLine(configs)}.`);
  return out.join('\n');
}

function main() {
  let values;
  try {
    ({ values } = parseArgs({
      options: {
        runs: { type: 'string', default: '5' },
        sizes: { type: 'string', default: '64,128,256,512,1024' },
        suite: { type: 'string', default: 'all' },
        json: { type: 'string' },
        report: { type: 'string' },
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
  if (values.report) {
    const saved = JSON.parse(fs.readFileSync(values.report, 'utf8'));
    const configs = saved.results.map((r) => ({ ...r, mode: MODES.find((m) => m.id === r.mode) }));
    console.log(report(saved.environment, configs, saved.sizes, saved.runs, saved.suite));
    return;
  }
  const runs = Number(values.runs);
  if (!Number.isInteger(runs) || runs < 1) fail(`Invalid --runs "${values.runs}": a whole number >= 1.`);
  const sizes = values.sizes.split(',').map(Number);
  if (sizes.some((s) => !Number.isInteger(s) || s < 1)) fail(`Invalid --sizes "${values.sizes}": whole numbers >= 1.`);
  if (!['all', 'modes', 'kernels'].includes(values.suite)) fail(`Invalid --suite "${values.suite}".`);

  const env = environment();
  run(process.execPath, [generator, '--pattern', 'all', '--sizes', sizes.join(','), '--out', benchDir]);

  const configs = configurations(values.suite, sizes);
  const started = Date.now();
  for (let r = 1; r <= runs; r++) {
    for (const [i, config] of configs.entries()) {
      const t = ditherOnce(config);
      config.times.push(t);
      console.error(`[round ${r}/${runs}, ${i + 1}/${configs.length}] ${config.size}² ${config.kernel}, ${config.mode.label}: ${ms(t)} ms`);
    }
    if (r === 1 && runs > 1) {
      console.error(`-- one round took ${minutes(Date.now() - started)}; about ${minutes((Date.now() - started) * (runs - 1))} to go`);
    }
  }
  for (const c of configs) c.median = median(c.times);

  console.log(report(env, configs, sizes, runs, values.suite));

  if (values.json) {
    const results = configs.map(({ key, size, kernel, mode, times, median: m }) =>
      ({ key, size, kernel, mode: mode.id, label: mode.label, image: mode.image, args: mode.args, times, median: m }));
    fs.writeFileSync(values.json, JSON.stringify({ environment: env, runs, sizes, suite: values.suite, results }, null, 2));
    console.error(`Wrote ${values.json}`);
  }
}

main();
