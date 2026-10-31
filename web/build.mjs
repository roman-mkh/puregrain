// Builds the web UI into web/dist/: the page's and the worker's scripts,
// each bundled by spago and esbuild into a self-running script, and the
// static files, the logo's icons and lockups included, with the library's
// version written into the page. Everything comes from our own build,
// nothing from a CDN (decision 19 in web/ROADMAP.md).
//
// Run from the repository's root: npm run web:build.
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';

const dist = 'web/dist';
// Afresh, so that nothing stays from an earlier build.
rmSync(dist, { recursive: true, force: true });
mkdirSync(dist, { recursive: true });

// spago resolves --outfile relative to the package's own folder, web/.
const bundle = (module, outfile) =>
  execFileSync(
    'npx',
    ['spago', 'bundle', '-p', 'puregrain-web', '--module', module,
      '--platform', 'browser', '--minify', '--outfile', `dist/${outfile}`],
    { stdio: 'inherit' },
  );

bundle('Puregrain.Web.Main', 'app.js');
bundle('Puregrain.Web.Worker', 'worker.js');
cpSync('web/static', dist, { recursive: true });

// The logo's files come from its folder, under the logo's own terms
// (logo/LICENSE.md), not MIT; web/static/ holds none of them.
for (const icon of ['favicon.ico', 'icon.svg', 'apple-touch-icon.png']) {
  copyFileSync(`logo/${icon}`, `${dist}/${icon}`);
}
for (const set of ['zx', 'c64']) {
  mkdirSync(`${dist}/logo/${set}`, { recursive: true });
  copyFileSync(`logo/${set}/lockup.png`, `${dist}/logo/${set}/lockup.png`);
}

// The library's version, from its spago.yaml, for the page's footer.
const version = /\n\s+publish:\s*\n\s+version:\s*([^\s#]+)/.exec(readFileSync('spago.yaml', 'utf8'))?.[1];
const empty = '<meta name="puregrain-version" content="">';
const page = readFileSync(`${dist}/index.html`, 'utf8');
if (!version || !page.includes(empty)) {
  throw new Error("Can't write the library's version into the page: check spago.yaml and web/static/index.html.");
}
writeFileSync(`${dist}/index.html`, page.replace(empty, `<meta name="puregrain-version" content="${version}">`));
