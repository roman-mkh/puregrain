// Builds the web UI into web/dist/: the page's and the worker's scripts,
// each bundled by spago and esbuild into a self-running script, and the
// static files, Pico CSS and the logo's icons included. Everything comes
// from our own build, nothing from a CDN (decision 19 in web/ROADMAP.md).
//
// Run from the repository's root: npm run web:build.
import { execFileSync } from 'node:child_process';
import { copyFileSync, cpSync, mkdirSync } from 'node:fs';

const dist = 'web/dist';
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
copyFileSync('node_modules/@picocss/pico/css/pico.min.css', `${dist}/pico.min.css`);
// The icons come from the logo's folder, under the logo's own terms
// (logo/LICENSE.md), not MIT; web/static/ holds none of them.
for (const icon of ['favicon.ico', 'icon.svg', 'apple-touch-icon.png']) {
  copyFileSync(`logo/${icon}`, `${dist}/${icon}`);
}
