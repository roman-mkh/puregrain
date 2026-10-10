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

import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');
const cli = path.join(root, 'cli', 'bin', 'puregrain-cli.mjs');
const generator = path.join(root, 'scripts', 'generate-images.mjs');
const benchDir = path.join(root, 'samples', 'bench');

// Quantizer modes, all with Floyd-Steinberg. RGB levels use 6 rather than
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

// Ordered dithering: the 8x8 Bayer map over 2 levels on the gray
// composite, without diffusion (kernel none) and combined with
// Floyd-Steinberg. Floyd-Steinberg with the threshold is the reference.
const BAYER = { id: 'bayer8', label: 'Bayer 8', image: 'gray', args: ['--bayer', '8'] };
const ALL_MODES = [...MODES, BAYER];
const SUITES = ['all', 'modes', 'kernels', 'ordered'];
const inSuite = (suite, name) => suite === 'all' || suite === name;

const USAGE = `Usage: node scripts/benchmark.mjs [options]

  --runs <n>      runs per configuration; the median is reported (default: 5)
  --sizes <list>  square image sides, comma-separated (default: 64,128,256,512,1024)
  --suite <s>     modes, kernels, ordered or all (default: all)
  --builds <list> build directories to compare, comma-separated (default: output). Each
                  configuration runs with every build back to back, the order alternating
                  by round; output-es is built by npm run build:es (purs-backend-es)
  --json <file>   also write every run's time, and the environment, as JSON
  --report <file> don't measure: print the tables for a JSON file written by --json`;

function fail(message) {
  console.error(`${message}\n\n${USAGE}`);
  process.exit(1);
}

const run = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8' }).trim();
const tryRun = (cmd, args) => { try { return run(cmd, args); } catch { return 'unknown'; } };

// Mains or battery: on a laptop, power management changes the CPU's
// clock speed, so runs are only comparable on the same power source.
// Linux lists power supplies under /sys/class/power_supply (visible even
// inside the Hyper-V VM this was developed in).
function powerSource() {
  const dir = '/sys/class/power_supply';
  const read = (p) => { try { return fs.readFileSync(p, 'utf8').trim(); } catch { return ''; } };
  let supplies;
  try { supplies = fs.readdirSync(dir); } catch { return 'unknown'; }
  const typed = supplies.map((s) => ({ type: read(`${dir}/${s}/type`), online: read(`${dir}/${s}/online`), status: read(`${dir}/${s}/status`) }));
  if (typed.some((s) => s.type === 'Mains' && s.online === '1')) return 'mains (AC)';
  const battery = typed.find((s) => s.type === 'Battery');
  return battery ? `battery${battery.status ? ` (${battery.status.toLowerCase()})` : ''}` : 'unknown';
}

function environment(builds) {
  const cpus = os.cpus();
  const dirty = tryRun('git', ['-C', root, 'status', '--porcelain']) !== '';
  return {
    date: new Date().toISOString().slice(0, 10),
    power: powerSource(),
    node: process.version,
    cpu: `${cpus[0]?.model ?? 'unknown'} (${cpus.length} logical cores)`,
    os: `${os.type()} ${os.release()} (${os.arch()})`,
    memory: `${Math.round(os.totalmem() / 2 ** 30)} GiB`,
    purs: tryRun(path.join(root, 'node_modules', '.bin', 'purs'), ['--version']),
    spago: tryRun(path.join(root, 'node_modules', '.bin', 'spago'), ['--version']),
    // purs-backend-es prints its version to stderr, as "v1.4.3".
    backend: builds.includes('output-es')
      ? (({ stdout, stderr }) => (stdout || stderr || 'unknown').trim().replace(/^v/, ''))(
        spawnSync(path.join(root, 'node_modules', '.bin', 'purs-backend-es'), ['--version'], { encoding: 'utf8' }))
      : undefined,
    commit: tryRun('git', ['-C', root, 'rev-parse', '--short', 'HEAD']) + (dirty ? ' (+ uncommitted changes)' : ''),
  };
}

// The configurations to measure. Floyd-Steinberg with the threshold is in
// every suite (the kernels' first row, the ordered suite's reference), and
// is measured once.
function configurations(suite, sizes) {
  const byKey = new Map();
  const add = (size, kernel, mode) => {
    const key = `${size}-${kernel}-${mode.id}`;
    if (!byKey.has(key)) byKey.set(key, { key, size, kernel, mode, times: [] });
  };
  for (const size of sizes) {
    if (inSuite(suite, 'modes')) for (const mode of MODES) add(size, 'floyd-steinberg', mode);
    if (inSuite(suite, 'kernels')) for (const kernel of KERNELS) add(size, kernel, MODES[0]);
    if (inSuite(suite, 'ordered')) {
      add(size, 'floyd-steinberg', MODES[0]);
      add(size, 'none', BAYER);
      add(size, 'floyd-steinberg', BAYER);
    }
  }
  return [...byKey.values()];
}

function ditherOnce(config) {
  const input = path.join(benchDir, `${config.mode.image}-${config.size}.png`);
  const output = path.join(benchDir, `out-${config.key.replace(':', '-')}.png`);
  // The launcher runs the build that PUREGRAIN_OUTPUT names (cli/bin).
  const stdout = execFileSync(process.execPath, [cli, input, output, '--kernel', config.kernel, ...config.mode.args],
    { encoding: 'utf8', env: { ...process.env, PUREGRAIN_OUTPUT: config.build } }).trim();
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

function environmentLines(env, runs, builds) {
  const out = ['**Environment:**', ''];
  out.push(`- Date: ${env.date}; commit ${env.commit}`);
  out.push(`- CPU: ${env.cpu}; memory: ${env.memory}`);
  out.push(`- Power: ${env.power ?? 'not recorded'}`);
  out.push(`- OS: ${env.os}`);
  out.push(`- Node ${env.node}; purs ${env.purs}; spago ${env.spago}` + (env.backend ? `; purs-backend-es ${env.backend}` : ''));
  if (builds.length > 1) {
    out.push(`- Builds: ${builds.map((b) => `\`${b}\``).join(', ')}; each configuration runs with every build back to ` +
      'back, the order alternating by round');
  }
  out.push(`- ${runs} runs per configuration, interleaved; median reported`);
  out.push('');
  return out.join('\n');
}

const KERNEL_LABELS = { 'floyd-steinberg': 'Floyd-Steinberg', atkinson: 'Atkinson', jjn: 'JJN', none: 'no diffusion' };

// Each further build against the first: the ratio of their medians, per
// configuration, at the three largest sizes.
function comparison(configs, sizes, builds) {
  const upper = sizes.slice(-3);
  const big = upper[upper.length - 1];
  const [base, ...others] = builds;
  const combos = configs.filter((c) => c.build === base && c.size === upper[0]).map(({ kernel, mode }) => ({ kernel, mode }));
  const out = [];
  for (const other of others) {
    const median1 = (build, size, kernel, modeId) =>
      configs.find((c) => c.build === build && c.size === size && c.kernel === kernel && c.mode.id === modeId).median;
    const ratio = (size, { kernel, mode }) => median1(other, size, kernel, mode.id) / median1(base, size, kernel, mode.id);
    out.push(`**\`${other}\` against \`${base}\`** (median ÷ median; below ×1.00, \`${other}\` is faster):`, '');
    const rows = combos.map((c) => [`${KERNEL_LABELS[c.kernel] ?? c.kernel}, ${c.mode.label}`, ...upper.map((s) => `×${ratio(s, c).toFixed(2)}`)]);
    out.push(table(['Configuration', ...upper.map((s) => `${s}²`)], rows), '');
    const all = combos.flatMap((c) => upper.map((s) => ratio(s, c)));
    const atBig = combos.map((c) => ratio(big, c));
    out.push(`Over ${upper[0]}² to ${big}²: median ×${median(all).toFixed(2)} (×${Math.min(...all).toFixed(2)} to ` +
      `×${Math.max(...all).toFixed(2)}); at ${big}²: median ×${median(atBig).toFixed(2)}.`, '');
  }
  return out.join('\n');
}

function report(env, configs, sizes, runs, suite, builds) {
  const out = [environmentLines(env, runs, builds)];
  if (builds.length === 1) {
    out.push(tables(configs, sizes, runs, suite));
  } else {
    for (const build of builds) {
      out.push(`#### Build \`${build}\``, '', tables(configs.filter((c) => c.build === build), sizes, runs, suite), '');
    }
    out.push('#### Comparison', '', comparison(configs, sizes, builds));
  }
  return out.join('\n');
}

function tables(configs, sizes, runs, suite) {
  const find = (size, kernel, modeId) => configs.find((c) => c.size === size && c.kernel === kernel && c.mode.id === modeId);
  // Growth per doubling of the side over the three largest sizes (a
  // geometric mean over two steps): a single step can be off by one noisy
  // median, and the smallest sizes are dominated by the fixed cold start.
  const upper = sizes.slice(-3);
  const perDoubling = (kernel, modeId) =>
    (find(upper[upper.length - 1], kernel, modeId).median / find(upper[0], kernel, modeId).median) ** (1 / (upper.length - 1));
  const upperLabel = `${upper[0]}²→${upper[upper.length - 1]}²`;
  const out = [];

  if (inSuite(suite, 'modes')) {
    out.push('**Quantizer modes** (Floyd-Steinberg; median ms, ×growth vs. the previous size):', '');
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

  if (inSuite(suite, 'kernels')) {
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

  // Runs saved before this suite existed have no ordered configurations.
  if (inSuite(suite, 'ordered') && configs.some((c) => c.mode.id === BAYER.id)) {
    out.push('**Ordered dithering** (Bayer 8×8 over 2 levels, gray; median ms):', '');
    const rows = sizes.map((size) => {
      const none = find(size, 'none', BAYER.id).median;
      const hybrid = find(size, 'floyd-steinberg', BAYER.id).median;
      const fs = find(size, 'floyd-steinberg', 'threshold').median;
      return [`${size}`, ms(none), ms(hybrid), ms(fs), `×${(none / fs).toFixed(2)}`, `×${(hybrid / fs).toFixed(2)}`];
    });
    if (upper.length >= 2) {
      rows.push([`per doubling, ${upperLabel}`, `×${perDoubling('none', BAYER.id).toFixed(2)}`,
        `×${perDoubling('floyd-steinberg', BAYER.id).toFixed(2)}`, `×${perDoubling('floyd-steinberg', 'threshold').toFixed(2)}`, '', '']);
    }
    out.push(table(['Side N', 'no diffusion', 'with FS', 'FS, threshold 128', 'no diffusion ÷ FS', 'with FS ÷ FS'], rows), '');
  }

  // Spread for the large sizes separately: at the small ones a ~0.1 s
  // timing is mostly cold start, which says little about the dithering.
  const spreadLine = (cs) => {
    const s = cs.map((c) => ({ key: c.key, s: spread(c.times) })).sort((a, b) => a.s - b.s);
    return `median ${(median(s.map((x) => x.s)) * 100).toFixed(0)}%, largest ${(s[s.length - 1].s * 100).toFixed(0)}% (${s[s.length - 1].key})`;
  };
  out.push(`**Run-to-run spread** ((max − min) ÷ median): ${upperLabel}: ${spreadLine(configs.filter((c) => upper.includes(c.size)))}; ` +
    `all sizes: ${spreadLine(configs)}.`);

  // Rounds are interleaved, so something else slowing the machine down for
  // a few minutes shows up as one round holding the slowest run of most
  // configurations. Medians ignore one bad round; this makes it visible.
  if (runs >= 3) {
    const large = configs.filter((c) => upper.includes(c.size));
    const slowest = Array(runs).fill(0);
    for (const c of large) slowest[c.times.indexOf(Math.max(...c.times))]++;
    const worst = slowest.indexOf(Math.max(...slowest));
    const line = `**Slowest run by round** (${upperLabel}, rounds 1-${runs}): ${slowest.join(' / ')}`;
    out.push('', slowest[worst] > large.length / 2
      ? `${line}. Round ${worst + 1} was slowest for ${slowest[worst]} of ${large.length} configurations: likely an outside ` +
        `disturbance during that round. The medians are unaffected; the spread figures include it.`
      : `${line}. No single round stands out.`);
  }
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
        builds: { type: 'string', default: 'output' },
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
    // Runs saved before --builds existed measured the purs build only.
    const configs = saved.results.map((r) => ({ ...r, build: r.build ?? 'output', mode: ALL_MODES.find((m) => m.id === r.mode) }));
    console.log(report(saved.environment, configs, saved.sizes, saved.runs, saved.suite, saved.builds ?? ['output']));
    return;
  }
  const runs = Number(values.runs);
  if (!Number.isInteger(runs) || runs < 1) fail(`Invalid --runs "${values.runs}": a whole number >= 1.`);
  const sizes = values.sizes.split(',').map(Number);
  if (sizes.some((s) => !Number.isInteger(s) || s < 1)) fail(`Invalid --sizes "${values.sizes}": whole numbers >= 1.`);
  if (!SUITES.includes(values.suite)) fail(`Invalid --suite "${values.suite}".`);
  const builds = values.builds.split(',').map((b) => b.trim()).filter((b) => b !== '');
  if (builds.length === 0 || new Set(builds).size !== builds.length) fail(`Invalid --builds "${values.builds}".`);
  for (const build of builds) {
    if (!fs.existsSync(path.join(root, build, 'Puregrain.Cli.Main', 'index.js'))) {
      fail(`No build in ${build}/: run ${build === 'output-es' ? 'npm run build:es' : 'npm run build'} first.`);
    }
  }

  const env = environment(builds);
  run(process.execPath, [generator, '--pattern', 'all', '--sizes', sizes.join(','), '--out', benchDir]);

  // One entry per configuration and build, the builds of a configuration
  // next to each other: they run back to back, so slow drift during the
  // session affects both alike, and alternating which goes first spreads
  // any effect of the order over both.
  const base = configurations(values.suite, sizes);
  const configs = base.flatMap((c) =>
    builds.map((build) => ({ ...c, key: builds.length > 1 ? `${build}:${c.key}` : c.key, build, times: [] })));
  const started = Date.now();
  for (let r = 1; r <= runs; r++) {
    const order = r % 2 === 1 ? builds : [...builds].reverse();
    let n = 0;
    for (let i = 0; i < base.length; i++) {
      for (const build of order) {
        const config = configs[i * builds.length + builds.indexOf(build)];
        const t = ditherOnce(config);
        config.times.push(t);
        n++;
        console.error(`[round ${r}/${runs}, ${n}/${configs.length}] ${builds.length > 1 ? `${build}, ` : ''}` +
          `${config.size}² ${config.kernel}, ${config.mode.label}: ${ms(t)} ms`);
      }
    }
    if (r === 1 && runs > 1) {
      console.error(`-- one round took ${minutes(Date.now() - started)}; about ${minutes((Date.now() - started) * (runs - 1))} to go`);
    }
  }
  for (const c of configs) c.median = median(c.times);

  console.log(report(env, configs, sizes, runs, values.suite, builds));

  if (values.json) {
    const results = configs.map(({ key, build, size, kernel, mode, times, median: m }) =>
      ({ key, build, size, kernel, mode: mode.id, label: mode.label, image: mode.image, args: mode.args, times, median: m }));
    fs.writeFileSync(values.json, JSON.stringify({ environment: env, runs, sizes, suite: values.suite, builds, results }, null, 2));
    console.error(`Wrote ${values.json}`);
  }
}

main();
