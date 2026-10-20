# puregrain-web — notes for working in `web/`

The web UI's own memory: its architecture and gotchas, which matter only
when working in `web/` (decision 18 in `ROADMAP.md`). The plan, the
decisions and the open questions are in `ROADMAP.md`; the library's and
the workspace's notes in the root `CLAUDE.md`.

## The package

- **Modules:** `Puregrain.Web.Main` (the page's entry: mounts the app on
  the body), `Puregrain.Web.App` (the component), `Puregrain.Web.Text`
  (every text the UI shows, decision 12), `Puregrain.Web.Worker` (the
  worker's entry). `web/static/` holds `index.html`, which loads
  `pico.min.css` and `app.js`.
- **Build:** `npm run web:build` (`web/build.mjs`) bundles the page into
  `web/dist/app.js` and the worker into `web/dist/worker.js`, minified,
  and copies `web/static/` and Pico's stylesheet next to them.
  `web/dist/` is gitignored. `npm run web:serve` serves it on
  http://localhost:8000; stop it with Ctrl+C.
- **Sizes** (phase 1, 2026-10-20): `app.js` 77.9 KB, 19.1 KB gzipped,
  almost all of it Halogen; `worker.js` 813 bytes; Pico 11.7 KB gzipped.

## Building

- **`spago bundle` resolves `--outfile` relative to the package's own
  folder** (`web/`), not the directory it runs in: `--outfile
  web/dist/app.js` wrote `web/web/dist/app.js`. `web/build.mjs` passes
  `dist/…`.
- **esbuild's server stops when its standard input closes** ("stopped
  automatically because stdin was closed"): fine in a terminal, but from
  a script without one, keep its input open, for example
  `tail -f /dev/null | npx esbuild --serve=… --servedir=…`.
- **`spago bundle` needs esbuild** (spago 1.0.4, checked in its code
  2026-10-20): it looks for an `esbuild` executable, so esbuild is a dev
  dependency. With `--platform browser` and the default bundle type
  `app`, it writes a self-running script (esbuild's `--format=iife`) that
  imports the module's `main` and calls it: right for the page's
  `<script>` and for a classic worker (`new Worker("worker.js")`). Module
  workers (`{ type: "module" }`) aren't needed; they'd require Firefox
  114 or later. spago refuses to overwrite a file it didn't write itself,
  unless `--force`.
- **esbuild's install script can be denied** in `allowScripts` (checked in
  0.28.2's `install.js`, 2026-10-20): it only swaps the JavaScript
  launcher `bin/esbuild` for the native binary, a speed-up, and checks the
  version. Without it, the launcher finds the platform binary that npm
  installs as an optional dependency (`@esbuild/linux-x64` and so on).
  Unlike `purescript`, whose script must run (root `CLAUDE.md`).
- **Serve over HTTP, even locally:** a browser won't start a worker for a
  page opened as a file (`file://`). esbuild can serve a folder (its
  serve options include `servedir`; entry points are optional).
- **Everything from our build** (decision 19, a self-contained static
  site): no CDN. JavaScript, ours and third-party, is bundled by esbuild;
  stylesheets and fonts are copied from their npm packages at build time.
- **Pico CSS** is `@picocss/pico` 2.1.1: MIT, no install script;
  `css/pico.min.css` is 83 KB, 11.7 KB gzipped.

## PureScript packages (package set 81.9.0)

- `halogen` 7.0.0 (the registry has 7.1.0, the sets up to 81.9.0 have
  7.0.0), `web-html`,
  `web-file`, `web-uievents`, `web-workers` 2.0.0, `canvas` 6.0.0,
  `arraybuffer-types`, `aff`, `js-promise-aff`.
- **`web-workers`:** `Web.Worker.Worker` (`new`, `postMessage`,
  `postMessage'` with transferables, `onMessage`, `terminate`); on the
  worker's side `Web.Worker.DedicatedWorkerGlobalScope` (`postMessage`,
  `onMessage`). Messages must be `IsSendable`: numbers, strings, arrays,
  records; anything else, a typed array say, through `unsafeWrap`.
  `MessageEvent`'s `data_` is a `Foreign`.
- **`canvas`:** `getContext2D`, `getImageData`, `putImageData`,
  `createImageData`, `imageDataBuffer` (a `Uint8ClampedArray`),
  `drawImage` (from a `CanvasImageSource`), `setFillStyle`, `fillRect`,
  `canvasToDataURL`. Missing, so a few lines of FFI: `createImageBitmap`,
  `toBlob`, and an `ImageBitmap` used as a `CanvasImageSource`.
- **No package binds `createImageBitmap`** (checked in the sets 81.4.0 and
  81.9.0: not `web-html` 4.1.1, `canvas`, `canvas-action`,
  `halogen-canvas`, `webb-file`). `canvas`'s `tryLoadImage` loads through
  an `<img>` element, which can't turn color conversion off (decision
  9), so it's our FFI: the call with `colorSpaceConversion: "none"`
  returns a Promise, which `js-promise-aff`'s `toAffE` makes an `Aff`.

## Browser facts

From MDN's browser-compat-data (2026-10-20); everything here works in
current Chrome, Edge, Firefox and Safari, the browsers v1 targets.

- **Decoding:** `createImageBitmap` takes the file itself (a `Blob`) and
  decodes whatever the browser can (PNG, JPEG, GIF, WebP and more). With
  `colorSpaceConversion: "none"` (Chrome 58, Firefox 98, Safari 15) it
  doesn't convert colors, so the stored values are dithered, as in the
  CLI. EXIF orientation is applied by default (`imageOrientation:
  "from-image"`), so phone photos come out upright.
- **Transparency:** a canvas keeps colors premultiplied by alpha, so fully
  transparent pixels lose theirs and read back black. Fill the canvas
  white first, then `drawImage`, then `getImageData` (decision 9).
- **Sharp pixels:** CSS `image-rendering: pixelated` (Firefox 93, Safari
  10). **The split view:** `clip-path` with `inset()` on the top layer.
- **Download:** `canvas.toBlob`, `URL.createObjectURL` and `<a download>`.
- **Workers:** classic workers and `terminate` everywhere; a message's
  `ArrayBuffer` can be transferred instead of copied.

## Checking in a real browser

Without Playwright (decision 14): the system's Firefox, headless, driven
through Marionette, its built-in remote control (length-prefixed JSON
over TCP, port 2828), by a few lines of Python from the standard
library. Phase 1's check loaded the page and read "The worker answered:
ping" from it.

- **Firefox here is a snap** (`/usr/bin/firefox` starts
  `/snap/bin/firefox`, version 157): it has a private `/tmp`, so a
  throwaway profile and any output go under
  `~/snap/firefox/common/` and are removed afterwards; never the
  user's own profile (`-no-remote -profile <dir>`).
- **`firefox --headless --screenshot`** shows the page but can't wait:
  it takes the picture at the load event, before a worker answers. To
  wait for something, use Marionette (`--marionette`, then
  `WebDriver:NewSession`, `WebDriver:Navigate`,
  `WebDriver:ExecuteScript` in a loop, `Marionette:Quit`).
