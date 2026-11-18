// Builds the npm package puregrain into npm/dist/, the folder that gets
// published (npm publish npm/dist): the command-line tool bundled into
// one file, cli.mjs, with the manifest, the README, the license and the
// third-party notices. pngjs stays a dependency, not bundled.
//
// Run from the repository's root: npm run npm:build.
import { chmodSync, copyFileSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { writeNotices } from '../scripts/third-party-notices.mjs';

const dist = 'npm/dist';
// Afresh, so that nothing stays from an earlier build.
rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });

// The library's version, from its spago.yaml: the package's and the
// command's (Puregrain.Cli.Options.version, checked against it).
const version = /\n\s+publish:\s*\n\s+version:\s*([^\s#]+)/.exec(readFileSync('spago.yaml', 'utf8'))?.[1];
if (!version) throw new Error("Can't read the library's version from spago.yaml.");
const tag = `v${version}`;

// Bundled as the lab's scripts are, by spago and esbuild; spago resolves
// --outfile relative to the package's own folder, cli/. pngjs is left
// out, and the code minified except for its names, so that stack traces
// in bug reports stay readable. One --bundler-args per esbuild option:
// spago passes each value to esbuild as a single argument, so options
// joined in one value reach it as one unreadable argument, which it
// ignores (seen 2026-11-18: pngjs was bundled and nothing minified).
execFileSync(
  'npx',
  ['spago', 'bundle', '-p', 'puregrain-cli', '--module', 'Puregrain.Cli.Main',
    '--platform', 'node', '--bundle-type', 'app', '--outfile', '../npm/dist/cli.mjs',
    '--bundler-args=--external:pngjs', '--bundler-args=--minify-whitespace',
    '--bundler-args=--minify-syntax'],
  { stdio: 'inherit' },
);
// spago's bundle for Node starts with the #! line that lets npm's link
// run it with Node, and imports pngjs rather than holding it; checked, so
// that a change in spago or in the options can't slip through.
const bundle = readFileSync(`${dist}/cli.mjs`, 'utf8');
if (!bundle.startsWith('#!/usr/bin/env node\n')) throw new Error("The bundle doesn't start with #!/usr/bin/env node: check spago's bundle.");
if (!/from\s*["']pngjs["']/.test(bundle) || bundle.includes('__commonJS')) {
  throw new Error('The bundle holds pngjs, or no import of it: check the --external option.');
}
chmodSync(`${dist}/cli.mjs`, 0o755);

// The manifest, with the version after the name.
const { name, ...rest } = JSON.parse(readFileSync('npm/package.json', 'utf8'));
writeFileSync(`${dist}/package.json`, `${JSON.stringify({ name, version, ...rest }, null, 2)}\n`);

// The README, its links to the repository's files pinned to the release's
// tag, so that a later change can't alter a published version's page.
const readme = readFileSync('npm/README.md', 'utf8')
  .replaceAll('github.com/roman-mkh/puregrain/blob/master/', `github.com/roman-mkh/puregrain/blob/${tag}/`)
  .replaceAll('raw.githubusercontent.com/roman-mkh/puregrain/master/', `raw.githubusercontent.com/roman-mkh/puregrain/${tag}/`);
if (readme.includes('/master/')) throw new Error('npm/README.md links to master in a way the build doesn\'t pin to the tag.');
writeFileSync(`${dist}/README.md`, readme);

// npm takes no file from a parent folder, so the license is copied in.
copyFileSync('LICENSE', `${dist}/LICENSE`);

const notices = writeNotices({
  entries: ['Puregrain.Cli.Main'],
  product: 'the npm package puregrain',
  into: "the npm package puregrain's bundle, cli.mjs",
  out: `${dist}/THIRD-PARTY-NOTICES.txt`,
  allowNpm: ['pngjs'],
});
console.log(`${dist}: puregrain ${version}; the notices list ${notices.packages.length} packages` +
  (notices.missing.length ? `, without a license text: ${notices.missing.join(', ')}` : ''));
