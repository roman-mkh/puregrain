# puregrain-web — notes for working in `web/`

The web UI's own memory: its architecture and gotchas, which matter only
when working in `web/` (decision 18 in `ROADMAP.md`). The plan, the
decisions and the open questions are in `ROADMAP.md`; the library's and
the workspace's notes in the root `CLAUDE.md`. The user docs are in
`README.md`, with the manual checklist (decision 14): when the UI
changes, keep its description, its table of the CLI's options and the
checklist in step.

## The package

- **Modules:** `Puregrain.Web.Main` (the page's entry: mounts the app on
  the body), `Puregrain.Web.App` (the component), `Puregrain.Web.Picture`
  (decoding and reading a picture with its transparency, exactly, drawing
  pixels; FFI in `Picture.js`), `Puregrain.Web.Prepare` (the
  background and the fit, decisions 22 and 27: the rules pure, the loops
  over a whole picture in `Prepare.js`, pinned to the rules by
  `PrepareSpec`),
  `Puregrain.Web.Zoom` (pure: the zoom levels and the canvas's CSS size),
  `Puregrain.Web.Screen` (the pixel ratio; FFI), `Puregrain.Web.Text`
  (every text the UI shows, decision 12), `Puregrain.Web.Settings` (pure:
  the choices, the target among them, the CLI's rules for them, and
  their message form), `Puregrain.Web.Dither` (pure: the settings as
  library values, as the CLI's `Pipeline` builds them; its gray
  conversion copied from there), `Puregrain.Web.Message` (the page's and
  the worker's messages, decoded with `foreign`), `Puregrain.Web.Pixels`
  (reading and writing rows of the RGBA bytes, rounding as the CLI's PNG
  writer, and a file's bytes; FFI), `Puregrain.Web.Run` (the row loop
  with the stepper, and a machine's band loop with its files, progress as
  a callback), `Puregrain.Web.Save` (the files' names and the tape's,
  pure, and the downloads; FFI), `Puregrain.Web.Worker` (the worker's
  entry: only its messaging). The page and the worker import the library
  through the `Puregrain` facade, and the specialty modules outside it
  (`Puregrain.Cells`, `Puregrain.Machine.*`) directly, as the CLI does;
  only the worker's bundle holds those. `web/static/` holds
  `index.html`, which loads `pico.min.css`, `app.css` and `app.js`.
- **Tests:** `web/test/`, `Test.Puregrain.Web.Main` listing the specs
  (`SettingsSpec`, `DitherSpec`, `MessageSpec`, `RunSpec`, `SaveSpec`,
  `ZoomSpec`), run by `spago test` with the other suites, in Node, so
  only modules that don't touch the browser at load (FFI that only uses
  the browser when called is fine). `RunSpec` pins the worker's row loop
  to the CLI's path: the same bytes as `ditherImage` on the whole
  picture, with the CLI's gray conversion and rounding, for 8 settings;
  and the band loop: the same pixels and files as `ditherCells` and the
  machines' writers, for 6 machine settings, with progress after each
  band. Seven deliberate breakages were all caught (v2's phase 1); one
  first slipped through, the Spectrum's normal colors mapped to its
  bright screen mode, since both sides used the same mapping: a spec
  pins the mapping against the library's modes now.
- **A run:** each change of the picture or a setting ends the worker and
  starts a new one with the settings, the size and a copy of the pixels
  (transferred), and the name for a ZX Spectrum tape; the worker answers
  with progress after every hundredth of the rows, or after each band of
  a machine's cells, then the result's pixels and, for a machine's screen
  of the screen's size, its files (all transferred). `runs` counts the
  runs, ended ones included, so an answer from an ended worker is
  dropped. While a run goes, the view shows the original.
- **A lazy list keeps every cell it has computed, for whatever holds its
  first cell.** The band loop reads rows through a lazy list and gets
  the bands as one, so a variable holding either list's start would
  keep the whole picture: measured on a 1024 × 4096 poster for the ZX
  Spectrum (Node, the live heap after a collection every 512 rows), it
  grew steadily to 417 MB. `Run` makes both lists afresh where they're
  consumed, from functions, so only the loop's reference moves along
  them: the heap stays within about 1 MB of the start.
- **The view:** two canvases stacked in `.layers`, the original below,
  drawn once per picture, and the result on top, drawn when a run
  finishes, before it's shown. Without a result it's hidden (the
  `hidden` property, which Pico makes `display: none`), and the slider
  and the download are unavailable. The result's `clip-path: inset(0 0 0
  X%)` cuts off its left part: X is the split, the range input's value
  in picture columns (0 to the width) as a share of the width, so the
  cut falls between screen pixels at every zoom and pixel ratio.
- **Zoom in screen pixels:** the canvas's CSS size is the picture's size
  × zoom ÷ `devicePixelRatio`, so each picture pixel is exactly zoom ×
  zoom screen pixels, also at fractional ratios (1.25, 1.5 on many
  laptops). A whole-number scale stays exact whatever the canvas's
  offset: checked at ratio 1.5 with a 1-pixel checkerboard in Firefox's
  screen-pixel screenshot (squares exactly 1 and 2 screen pixels at 1×
  and 2×, phase 2). The browser's zoom changes the ratio and fires
  `resize`, which the app listens to.
- **Build:** `npm run web:build` (`web/build.mjs`) bundles the page into
  `web/dist/app.js` and the worker into `web/dist/worker.js`, minified,
  and copies `web/static/` and Pico's stylesheet next to them.
  `web/dist/` is gitignored. `npm run web:serve` serves it on
  http://localhost:8000; stop it with Ctrl+C.
- **Sizes** after v2's phase 2: `app.js` 135.2 KB, 33.7 KB gzipped
  (77.9 KB, 19.1 KB gzipped after v1's phase 1: mostly Halogen);
  `worker.js` 71.2 KB, 18.8 KB gzipped, with the library (since v1's
  phase 3) and the machines' modules; Pico 11.7 KB gzipped.
- **Preparing a picture** (v2's phase 2): the page keeps the picture as
  read, and makes from it what's shown as the original and dithered: put
  onto the background when it has transparency, fitted to a machine's
  screen when asked. A new target, fit or background prepares it again
  and restarts the run; the fit and the background stay for the next
  picture. It runs on the page, not in a worker: measured in Node, the
  fit takes 73 ms for a 12.6-megapixel picture and 158 ms for 48, the
  flattening 68 and 220 ms (a lookup table per channel; computing every
  pixel's mix took 326 ms).
- **The fit's area averaging is exact:** each screen pixel's weights are
  whole numbers (the overlaps, counted in units of 1/m of a picture
  pixel along an axis of n pixels scaled to m), so every sum is a whole
  number below 2^53, exact in a double whatever the order of adding, and
  the mean rounded with `Math.round`. A later PureScript version, for
  the CLI's `--fit`, gives the same bytes if it keeps these weights.

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
  returns a Promise, which `aff-promise`'s `toAffE` makes an `Aff`
  (`aff-promise` rather than `js-promise-aff`: its `Control.Promise`
  brings the `Promise` type in the same package).
- **Facts for v2's machine path** (checked 2026-10-22):
  - `Data.List.Lazy`'s `unfoldr` (lists 7.0.1) calls its step function
    inside `defer`, only when that cell is forced, so it can read rows
    as they're needed.
  - `Puregrain.Cells.ditherBands` does all its work inside `defer`, and
    `ditherCells` is the same bands concatenated: the file writers'
    `{ cells, image }` record can be built from the bands.
  - `web-file`'s `Blob` (`fromString`, `fromArray`) takes only strings:
    a blob of bytes needs FFI.
  - The clock: `Effect.Now.now` from the `now` package (6.0.0, in the
    set); `web-html` 4.1.1 binds no `performance`.

## Browser facts

From MDN's browser-compat-data (2026-10-20); everything here works in
current Chrome, Edge, Firefox and Safari, the browsers v1 targets.

- **Decoding:** `createImageBitmap` takes the file itself (a `Blob`) and
  decodes whatever the browser can (PNG, JPEG, GIF, WebP and more). With
  `colorSpaceConversion: "none"` (Chrome 58, Firefox 98, Safari 15) it
  doesn't convert colors, so the stored values are dithered, as in the
  CLI. EXIF orientation is applied by default (`imageOrientation:
  "from-image"`), so phone photos come out upright.
- **Transparency:** a 2D canvas keeps colors premultiplied by alpha, so
  fully transparent pixels lose theirs and semi-transparent ones come
  back rounded: measured in Firefox (v2's phase 2) on a picture with
  every alpha for every value, 97,155 of 195,840 color values were off,
  by up to 254 at low alpha. The page reads such a picture through
  WebGL: `createImageBitmap` with `premultiplyAlpha: "none"`, a texture
  with `UNPACK_PREMULTIPLY_ALPHA_WEBGL` false and no color conversion,
  attached to a framebuffer and read with `readPixels`: every value
  exact (WebGL 1 and 2; textures up to 16,384 on a side here). Without
  WebGL (`webgl.disabled`, checked) it falls back to the canvas, and
  the flattened values are off by 1 in 37% of them. An opaque picture is
  read from the canvas, exactly.
- **The browser's own compositing isn't the formula:** filling a canvas
  with a color and drawing a semi-transparent picture over it gave
  values off by 1 or 2 from color × alpha + background × (1 − alpha),
  rounded, in a third to a half of them (Firefox). v1's check, "exact to
  the value", had tried one sample. So the page flattens with its own
  formula (decision 27).
- **The browser's scaling aliases:** `drawImage` scaling a 2048 × 1536
  zone plate to 256 × 192 shows strong moiré at every smoothing quality
  in Firefox; `createImageBitmap`'s `resizeQuality: "high"` is clean,
  but each browser has its own filter. The page scales with its own area
  averaging (decision 22).
- **Checked in phase 2** (Firefox 157, ratios 1 and 1.5): a plain PNG
  reads back exactly; a PNG with a gAMA chunk (gamma 1.0) too, while the
  same file through an `<img>` element comes back converted (137,447 of
  192,000 channel values changed), so `colorSpaceConversion: "none"` is
  in effect; transparent parts became white (v1 then let the browser
  flatten them; see "Transparency" for why v2 doesn't).
- **A canvas's `width` or `height` set clears it.** Halogen's virtual DOM
  sets only the properties that changed, so a zoom change (a new CSS
  size) keeps the picture; a new picture gets a new canvas, drawn after
  the state change rendered it (`getHTMLElementRef`, then
  `putImageData`).
- **Drops:** the whole `main` takes them, so that a drop beside the input
  doesn't make the browser open the file; `dragover` must call
  `preventDefault`, or the browser refuses the drop.
- **Halogen matches unkeyed children by position.** When an element
  before the canvas comes or goes (the progress bar, say), the canvas is
  rebuilt as a new, blank element, and drawing through the old reference
  misses it: phase 3's first browser check read a blank canvas. Parts
  whose elements come and go sit in fixed containers (`.settings`,
  `.status`), so the canvas keeps its place.
- **`web-workers` 2.0.0 can't send a record as such:** its `IsSendable`
  instance for records needs `IsSendableRowList`, which it doesn't
  export ("the class was not in scope"). Each message is sent wrapped
  with `unsafeWrap`; the records hold only plain data and typed arrays,
  and the receiving side decodes them (`Puregrain.Web.Message`).
- **Sharp pixels:** CSS `image-rendering: pixelated` (Firefox 93, Safari
  10). **The split view:** `clip-path` with `inset()` on the top layer.
- **Download:** `canvas.toBlob`, `URL.createObjectURL` and `<a download>`.
  The link needn't be in the page: the HTML standard lets an `a` element
  follow its link unconnected ("cannot navigate" excepts `a` elements).
  The download fetches the file after the click has returned, so the URL
  is revoked 40 s later, as FileSaver.js does.
- **Firefox's PNG** from `toBlob` (version 157, a fresh profile) is RGBA
  (color type 6) with a private chunk `deBG` after the image data: 16
  hex digits made from its fingerprinting protection's randomization key
  and the image's hash (`nsPNGEncoder::MaybeAddCustomMetadata` in its
  source). The pixels are exact; only the file's bytes vary.
- **Workers:** classic workers and `terminate` everywhere; a message's
  `ArrayBuffer` can be transferred instead of copied.

## Checking in a real browser

Without Playwright (decision 14): the system's Firefox, headless, driven
through Marionette, its built-in remote control (length-prefixed JSON
over TCP, port 2828), by a few lines of Python from the standard library
(phases 1 to 3) or of Node (phase 4: a client of about 40 lines on
`node:net`, with pngjs reading screenshots and downloads). Phase 1's
check loaded the page and read "The worker answered: ping" from it.

- **Firefox here is a snap** (`/usr/bin/firefox` starts
  `/snap/bin/firefox`, version 157): it has a private `/tmp`, so a
  throwaway profile and any output go under
  `~/snap/firefox/common/` and are removed afterwards; never the
  user's own profile (`-no-remote -profile <dir>`).
- **Useful Marionette commands:** `WebDriver:ElementSendKeys` with a file
  path chooses that file in an `<input type="file">` (the path must be
  readable by the snap); a synthetic drop works as
  `new DragEvent("drop", { dataTransfer })` with `new DataTransfer()`
  holding a `File`; `WebDriver:TakeScreenshot` gives screen pixels.
- **Checked in phase 3:** for 7 settings (a threshold, levels with
  Atkinson, a palette with JJN, pure Bayer, the hybrid, a palette after
  "gray first", 3 levels), the page's result on the color composite at
  320×200 equals the CLI's output, all 192,000 channel values. A
  1024×1024 run shows rising progress, the page answers within a few
  milliseconds meanwhile, and Cancel ends it, shows the original, and
  no late answer is applied.
- **Checked in phase 4:** the view shows the original left of the split
  and the result right of it, exact to the screen pixel, at ratio 1
  (zoom 1× at splits 0, 1, 37, 160, 319 and 320, and 3×) and at 1.5 (1×
  and 2×); the split stays across runs and is back in the middle for a
  new picture. The downloads (4 levels with Atkinson, a threshold with
  Floyd–Steinberg) have the CLI's pixel values and the settings' names.
  While a run goes and after Cancel, the result is hidden, the slider
  disabled, and no download offered.
- **Checked in v2's phase 1:** on the color composites at the screens'
  sizes, the page's ZX Spectrum screen (the 8×8 Bayer map; the bright
  colors with Atkinson) and C64 screen (the 8×8 map) equal the CLI's,
  every pixel, and the downloaded `.scr`, `.tap`, `.prg` and `.art`
  are byte for byte the CLI's files; the 512 × 512 composite gives the
  CLI's poster, with the size note and the PNG button only. The target's
  menus, the hint and the return to any screen work as decision 21
  says.
- **Checked in v2's phase 2:** a picture with every alpha for every
  value, put onto white and onto #2a5ac8, equals the formula on the
  file's own values, all 196,608 channel values, and dithered with 4
  levels equals the CLI's result on that flattened picture. A 2048 ×
  1536 picture fitted to the ZX Spectrum's screen equals the area
  averaging worked out independently in Node; dithered with the 8×8 map,
  it's the CLI's result on that fitted picture, and the `.scr` and
  `.tap` are the CLI's, byte for byte. A 2400 × 1600 picture comes out
  288 × 192, cropped, and a 100 × 80 icon centered on black, each equal
  to the reference, each with its note; the fit and the background stay
  for the next picture, and the names carry `fit` and `bg-`.
- **`WebDriver:Navigate` reloads the page,** and with it every setting:
  a check that loads one picture after another with the same settings
  must choose the next file in the same page, by sending it to the file
  input again.
- **Downloads** go straight into a folder with these in the profile's
  `user.js`: `browser.download.folderList` 2, `browser.download.dir`,
  `browser.download.useDownloadDir` true and
  `browser.download.always_ask_before_handling_new_types` false; for a
  machine's files, `browser.helperApps.neverAsk.saveToDisk` names
  `application/octet-stream` too.
  `marionette.port` (2829, say) moves Marionette off its default port.
- **A dev server may already be running on port 8000,** the user's own
  (`npm run web:serve`): checks use another port (8001), and stop only
  their own server. The user's own Firefox may be running too: a check's
  Firefox runs with `-no-remote` and its own profile beside it.
- **Another pixel ratio:** a profile's `user.js` with
  `user_pref("layout.css.devPixelsPerPx", "1.5");` makes Firefox's ratio
  1.5, like many laptops.
- **`firefox --headless --screenshot`** shows the page but can't wait:
  it takes the picture at the load event, before a worker answers. To
  wait for something, use Marionette (`--marionette`, then
  `WebDriver:NewSession`, `WebDriver:Navigate`,
  `WebDriver:ExecuteScript` in a loop, `Marionette:Quit`).
