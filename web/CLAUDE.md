# puregrain-web — notes for working in `web/`

The web UI's own memory: its architecture and gotchas, which matter only
when working in `web/` (decision 18 in `ROADMAP.md`). The plan, the
decisions and the open questions are in `ROADMAP.md`; the library's and
the workspace's notes in the root `CLAUDE.md`.

## Building

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

## PureScript packages (package set 81.4.0)

- `halogen` 7.0.0 (the registry has 7.1.0, the set 7.0.0), `web-html`,
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
