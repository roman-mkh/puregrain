// Third-party notices for a bundle: the PureScript packages whose compiled
// code a bundle can contain, each with its license in full. The bundles
// (puregrain lab's scripts, the npm package's cli.mjs) are a binary form in
// the licenses' sense, and most of these packages' BSD-style licenses ask
// that "redistributions in binary form must reproduce the above copyright
// notice". Used by web/build.mjs and npm/build.mjs, or on its own:
//
//   node scripts/third-party-notices.mjs --entry Puregrain.Web.Main \
//     --entry Puregrain.Web.Worker --product "puregrain lab" \
//     --into "puregrain lab's scripts, app.js and worker.js" \
//     --out web/dist/THIRD-PARTY-NOTICES.txt
//
// Run from the repository's root, after a build (it reads output/).
//
// Which packages: it follows the compiled modules' imports from the entry
// modules, so it finds every module a bundle can contain, whatever the
// bundler drops; a notice too many does no harm, one too few would. Each
// module's source in .spago/p/<name>-<version>/src/ names its package, the
// version from spago.lock. The workspace's own modules are puregrain's,
// under its LICENSE, and aren't listed. Imports of npm packages are
// dependencies of the package, not bundled: each must be named with
// --allow-npm, so a new one can't slip into a bundle unnoticed.
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { builtinModules } from 'node:module';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const ownLicense = 'https://github.com/roman-mkh/puregrain/blob/master/LICENSE';
const rule = '-'.repeat(72);

// Every .purs file under a folder, with the module it declares.
function modulesIn(dir) {
  const found = [];
  const walk = d => {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const path = join(d, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.name.endsWith('.purs')) {
        const name = /^module\s+([A-Z][\w.]*)/m.exec(readFileSync(path, 'utf8'))?.[1];
        if (name) found.push(name);
      }
    }
  };
  if (existsSync(dir)) walk(dir);
  return found;
}

// Module name -> its package (a registry package from spago.lock), or
// null for the workspace's own modules.
function moduleIndex() {
  const lock = JSON.parse(readFileSync('spago.lock', 'utf8'));
  const index = new Map();
  for (const [name, info] of Object.entries(lock.packages)) {
    const dir = `.spago/p/${name}-${info.version}`;
    if (!existsSync(dir)) throw new Error(`${dir} is missing: run a build first.`);
    for (const module of modulesIn(`${dir}/src`)) index.set(module, { name, version: info.version, dir });
  }
  for (const pkg of Object.values(lock.workspace.packages)) {
    for (const module of modulesIn(join(pkg.path, 'src'))) index.set(module, null);
  }
  return index;
}

// The specifiers a compiled file imports, static and dynamic.
function importsOf(file) {
  const text = readFileSync(file, 'utf8');
  const found = new Set();
  const patterns = [
    /(?:^|\s)(?:import|export)\s+(?:[^'"]*?\s+from\s+)?['"]([^'"]+)['"]/g,
    /\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
    /\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
  ];
  for (const pattern of patterns) for (const match of text.matchAll(pattern)) found.add(match[1]);
  return [...found];
}

const isBuiltin = spec => spec.startsWith('node:') || builtinModules.includes(spec.split('/')[0]);

// The packages reachable from the entry modules, and the npm imports met.
export function packagesOf(entries, output = 'output') {
  const index = moduleIndex();
  const packages = new Map();
  const npm = new Set();
  const seen = new Set();
  const visit = module => {
    if (seen.has(module)) return;
    seen.add(module);
    if (!index.has(module)) throw new Error(`No package has the module ${module}.`);
    const pkg = index.get(module);
    if (pkg) packages.set(pkg.name, pkg);
    const files = [`${output}/${module}/index.js`, `${output}/${module}/foreign.js`].filter(existsSync);
    if (files.length === 0) throw new Error(`${output}/${module}/index.js is missing: run a build first.`);
    for (const file of files) {
      for (const spec of importsOf(file)) {
        const compiled = /^\.\.\/([^/]+)\/index\.js$/.exec(spec);
        if (compiled) visit(compiled[1]);
        else if (spec === './foreign.js' || isBuiltin(spec)) continue;
        else if (spec.startsWith('.') || spec.startsWith('/')) throw new Error(`${file} imports ${spec}, a file this script can't place.`);
        else npm.add(spec.startsWith('@') ? spec.split('/').slice(0, 2).join('/') : spec.split('/')[0]);
      }
    }
  };
  for (const entry of entries) visit(entry);
  return { packages: [...packages.values()].sort((a, b) => a.name.localeCompare(b.name)), npm: [...npm].sort() };
}

// A package's manifest (purs.json) and license file, if it has one.
function details(pkg) {
  const manifest = JSON.parse(readFileSync(`${pkg.dir}/purs.json`, 'utf8'));
  const loc = manifest.location ?? {};
  const source = loc.githubOwner ? `https://github.com/${loc.githubOwner}/${loc.githubRepo}` : (loc.gitUrl ?? '');
  const file = readdirSync(pkg.dir).find(f => /^licen[cs]e(\.(md|txt))?$/i.test(f));
  return { spdx: manifest.license ?? 'unknown', source, ref: manifest.ref, text: file ? readFileSync(`${pkg.dir}/${file}`, 'utf8').trim() : null };
}

// Prose wrapped at 72 columns, words kept whole (a URL may run over).
function wrap(text) {
  const lines = [];
  let line = '';
  for (const word of text.split(/\s+/)) {
    if (line && line.length + 1 + word.length > 72) { lines.push(line); line = word; }
    else line = line ? `${line} ${word}` : word;
  }
  if (line) lines.push(line);
  return lines;
}

// The notices as plain text, which every browser shows as it is.
export function noticesText({ product, into, packages }) {
  const rows = packages.map(pkg => ({ ...pkg, ...details(pkg) }));
  const width = Math.max(...rows.map(r => `${r.name} ${r.version}`.length));
  const spdxWidth = Math.max(...rows.map(r => r.spdx.length));
  return [
    `Third-party notices for ${product}`,
    '',
    ...wrap(`The PureScript packages below are compiled into ${into}, each used under its license, which follows the list in full. puregrain's own code is under the MIT license: ${ownLicense}`),
    '',
    ...rows.map(r => `  ${`${r.name} ${r.version}`.padEnd(width)}  ${r.spdx.padEnd(spdxWidth)}  ${r.source}`),
    ...rows.flatMap(r => [
      '',
      rule,
      `${r.name} ${r.version} (${r.spdx})`,
      r.source && r.ref ? `${r.source}/tree/${r.ref}` : r.source,
      rule,
      '',
      ...(r.text === null ? wrap(`No license file in its published package or its repository; its manifest names the ${r.spdx} license.`) : [r.text]),
    ]),
    '',
  ].join('\n');
}

// Writes the notices, and returns what they list, for the builds to report.
export function writeNotices({ entries, product, into, out, allowNpm = [], output = 'output' }) {
  const { packages, npm } = packagesOf(entries, output);
  const unexpected = npm.filter(name => !allowNpm.includes(name));
  if (unexpected.length > 0) {
    throw new Error(`${entries.join(', ')} import npm packages not allowed for this bundle: ${unexpected.join(', ')}.`);
  }
  writeFileSync(out, noticesText({ product, into, packages }));
  const missing = packages.filter(pkg => details(pkg).text === null).map(pkg => pkg.name);
  return { packages: packages.map(pkg => `${pkg.name} ${pkg.version}`), npm, missing };
}

if (process.argv[1] && relative(process.argv[1], fileURLToPath(import.meta.url)) === '') {
  const args = process.argv.slice(2);
  const all = flag => args.flatMap((a, i) => (a === flag ? [args[i + 1]] : []));
  const one = flag => all(flag)[0];
  if (all('--entry').length === 0 || !one('--out') || !one('--product') || !one('--into')) {
    console.error('Usage: node scripts/third-party-notices.mjs --entry MODULE... --product NAME --into TEXT --out FILE [--allow-npm NAME...]');
    process.exit(1);
  }
  const result = writeNotices({ entries: all('--entry'), product: one('--product'), into: one('--into'), out: one('--out'), allowNpm: all('--allow-npm') });
  console.log(`${one('--out')}: ${result.packages.length} packages${result.missing.length ? `; without a license text: ${result.missing.join(', ')}` : ''}${result.npm.length ? `; npm imports (dependencies, not listed): ${result.npm.join(', ')}` : ''}`);
}
