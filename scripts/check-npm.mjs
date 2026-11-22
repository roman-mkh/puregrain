// End-to-end checks of the npm package puregrain, as users get it:
//
//   npm run npm:build && npm run check:npm
//
// It packs npm/dist/ as `npm publish` would, installs the tarball into an
// empty folder in the system's temporary directory (pngjs comes from the
// npm registry then, not from this repository, so it needs the network),
// and runs the installed command through npm's own link:
//
//   1. the tarball holds exactly the package's five files;
//   2. --version, the usage line and the engine check, under the name
//      `puregrain`, whatever the link's file is called;
//   3. the installed command's files equal the launcher's, byte for byte,
//      for gray, color, a gamma, a palette, a Bayer map, serpentine
//      scanning and the machines' files;
//   4. nothing can be imported from the package but its package.json;
//   5. the third-party notices list every PureScript package esbuild puts
//      into the CLI's bundle and into puregrain lab's, each with its
//      license text, or one of the packages known to have none.
//
// Stops at the first failure, with exit code 1. Run from anywhere.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';
import { packagesOf } from './third-party-notices.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
process.chdir(root);

// Packages with no license text in their package or their repository,
// only a license named in their manifests (checked 2026-11-18). Another
// one fails the check until someone has looked at it and added it here.
const knownWithoutText = ['exitcodes', 'freeap'];

const pass = message => console.log(`PASS  ${message}`);
class Failure extends Error {}
const fail = message => { throw new Failure(message); };
const run = (command, args, options = {}) => execFileSync(command, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...options });

const version = /\n\s+publish:\s*\n\s+version:\s*([^\s#]+)/.exec(readFileSync('spago.yaml', 'utf8'))?.[1];
const tmp = mkdtempSync(join(tmpdir(), 'puregrain-check-npm-'));
try {
  if (!existsSync('npm/dist/package.json')) fail('npm/dist/ is missing: run npm run npm:build first.');
  const built = JSON.parse(readFileSync('npm/dist/package.json', 'utf8')).version;
  if (built !== version) fail(`npm/dist/ holds version ${built}, spago.yaml says ${version}: run npm run npm:build again.`);

  // The inputs, as check:cli makes its own.
  const inputs = 'samples/check-npm';
  mkdirSync(inputs, { recursive: true });
  for (const [pattern, size] of [['gray', '512'], ['color', '512'], ['color', '256x192'], ['color', '320x200']]) {
    run('node', ['scripts/generate-images.mjs', '--pattern', pattern, '--size', size, '--out', inputs]);
  }

  // 1. The tarball, packed as npm publish would pack it.
  const [packed] = JSON.parse(run('npm', ['pack', '--json', '--pack-destination', tmp], { cwd: 'npm/dist' }));
  const files = packed.files.map(f => f.path).sort();
  const expected = ['LICENSE', 'README.md', 'THIRD-PARTY-NOTICES.txt', 'cli.mjs', 'package.json'];
  if (JSON.stringify(files) !== JSON.stringify(expected)) fail(`the tarball holds ${files.join(', ')}, not ${expected.join(', ')}`);
  pass(`npm pack: ${packed.filename}, exactly ${files.length} files (${(packed.size / 1000).toFixed(1)} kB)`);

  // Installed into an empty folder, from the tarball and the npm registry.
  const app = join(tmp, 'app');
  mkdirSync(app);
  writeFileSync(join(app, 'package.json'), '{ "name": "check-npm", "private": true }\n');
  run('npm', ['install', join(tmp, packed.filename), '--no-audit', '--no-fund', '--ignore-scripts', '--loglevel=error'], { cwd: app });
  const pngjs = JSON.parse(readFileSync(join(app, 'node_modules/pngjs/package.json'), 'utf8')).version;
  if (!pngjs.startsWith('7.0.')) fail(`npm installed pngjs ${pngjs}, outside ~7.0.0`);
  pass(`npm install of the tarball into an empty folder: puregrain ${version}, pngjs ${pngjs} from the registry`);

  // 2. The command, through npm's link (its file name isn't the command's).
  const bin = join(app, 'node_modules/.bin/puregrain');
  const shown = run(bin, ['--version'], { cwd: app }).trim();
  if (shown !== `puregrain ${version}`) fail(`--version printed "${shown}", not "puregrain ${version}"`);
  const usage = run(bin, ['--help'], { cwd: app }).split('\n').find(line => line.startsWith('Usage:'));
  if (!usage?.startsWith('Usage: puregrain (')) fail(`the usage line reads "${usage}"`);
  const engine = run(bin, ['--check-engine'], { cwd: app }).trim();
  if (!engine.startsWith('Engine check passed')) fail(`--check-engine said "${engine}"`);
  pass(`the installed command: "${shown}", "Usage: puregrain (...", the engine check passed`);

  // 3. The installed command's files against the launcher's.
  const configurations = [
    ['gray-512.png', 'png', []],
    ['color-512.png', 'png', ['--levels', '4', '--kernel', 'atkinson', '--gamma', 'srgb']],
    ['color-512.png', 'png', ['--palette', 'c64']],
    ['color-512.png', 'png', ['--gray', '--bayer', '8']],
    ['gray-512.png', 'png', ['--kernel', 'jjn', '--serpentine']],
    ['color-256x192.png', 'scr', ['--machine', 'zx-spectrum', '--bayer', '2']],
    ['color-256x192.png', 'tap', ['--machine', 'zx-spectrum', '--bayer', '2']],
    ['color-320x200.png', 'prg', ['--machine', 'c64-hires', '--bayer', '2']],
  ];
  // The same file name for both, in two folders: a tape carries its name.
  mkdirSync(join(tmp, 'installed'));
  mkdirSync(join(tmp, 'launcher'));
  for (const [input, format, options] of configurations) {
    const source = join(root, inputs, input);
    const ours = join(tmp, 'installed', `out.${format}`);
    const theirs = join(tmp, 'launcher', `out.${format}`);
    run(bin, [source, ours, ...options], { cwd: app });
    run('node', ['cli/bin/puregrain-cli.mjs', source, theirs, ...options]);
    if (!readFileSync(ours).equals(readFileSync(theirs))) fail(`${input} ${options.join(' ')} -> .${format}: the installed command's file differs from the launcher's`);
    pass(`${input} ${options.join(' ') || '(the defaults)'} -> .${format}: the launcher's bytes`);
  }

  // 4. Nothing to import but the package.json.
  const tryImport = spec => run('node', ['--input-type=module', '-e',
    `import(${JSON.stringify(spec)}).then(() => console.log('imported'), e => console.log(e.code))`], { cwd: app }).trim();
  for (const spec of ['puregrain', 'puregrain/cli.mjs']) {
    const result = tryImport(spec);
    if (result !== 'ERR_PACKAGE_PATH_NOT_EXPORTED') fail(`import("${spec}") gave ${result}, not ERR_PACKAGE_PATH_NOT_EXPORTED`);
  }
  const manifest = run('node', ['-e', "console.log(require('puregrain/package.json').version)"], { cwd: app }).trim();
  if (manifest !== version) fail(`require("puregrain/package.json") gave ${manifest}`);
  pass('imports: "puregrain" and "puregrain/cli.mjs" refused (ERR_PACKAGE_PATH_NOT_EXPORTED), "puregrain/package.json" allowed');

  // 5. The notices against what esbuild bundles. The modules' packages are
  // found here by their source files' paths, independently of the notices
  // script, which reads their module lines.
  const lock = JSON.parse(readFileSync('spago.lock', 'utf8'));
  const packageOf = new Map();
  for (const [name, info] of Object.entries(lock.packages)) {
    const walk = (dir, prefix) => {
      if (!existsSync(dir)) return;
      for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isDirectory()) walk(join(dir, entry.name), `${prefix}${entry.name}.`);
        else if (entry.name.endsWith('.purs')) packageOf.set(prefix + entry.name.slice(0, -5), name);
      }
    };
    walk(`.spago/p/${name}-${info.version}/src`, '');
  }
  const bundles = [
    { label: "the CLI's bundle", entries: ['Puregrain.Cli.Main'], platform: 'node', notices: 'npm/dist/THIRD-PARTY-NOTICES.txt' },
    { label: "puregrain lab's scripts", entries: ['Puregrain.Web.Main', 'Puregrain.Web.Worker'], platform: 'browser', notices: null },
  ];
  for (const { label, entries, platform, notices } of bundles) {
    const bundled = new Set();
    for (const entry of entries) {
      const result = await esbuild.build({
        stdin: { contents: `import { main } from './output/${entry}/index.js'; main();`, resolveDir: root, sourcefile: 'entry.mjs' },
        bundle: true, platform, format: 'esm', external: ['pngjs'], minify: true, write: false, metafile: true, logLevel: 'error',
      });
      const output = Object.values(result.metafile.outputs)[0];
      for (const [path, info] of Object.entries(output.inputs)) {
        const module = /(?:^|\/)output\/([^/]+)\//.exec(path)?.[1];
        if (module && info.bytesInOutput > 0 && packageOf.has(module)) bundled.add(packageOf.get(module));
      }
    }
    const listed = packagesOf(entries);
    const names = new Set(listed.packages.map(p => p.name));
    const missing = [...bundled].filter(name => !names.has(name));
    if (missing.length) fail(`${label}: bundled but not in the notices: ${missing.join(', ')}`);
    if (notices) {
      const text = readFileSync(notices, 'utf8');
      const absent = listed.packages.filter(p => !text.includes(`\n${p.name} ${p.version} (`));
      if (absent.length) fail(`${notices} lacks ${absent.map(p => p.name).join(', ')}`);
    }
    const withoutText = listed.packages.filter(p => !readdirSync(p.dir).some(f => /^licen[cs]e(\.(md|txt))?$/i.test(f))).map(p => p.name);
    const unknown = withoutText.filter(name => !knownWithoutText.includes(name));
    if (unknown.length) fail(`${label}: no license text in ${unknown.join(', ')}; look at them, then add them to knownWithoutText`);
    pass(`${label}: the notices list all ${bundled.size} packages esbuild bundles (${names.size} listed)` +
      (withoutText.length ? `; known to have no license text: ${withoutText.join(', ')}` : ''));
  }
} catch (error) {
  if (!(error instanceof Failure)) throw error;
  console.log(`FAIL  ${error.message}`);
  process.exitCode = 1;
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
