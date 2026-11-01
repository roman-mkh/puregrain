# puregrain-web — notes for working in `web/`

The web UI's own memory: its architecture and gotchas, which matter only
when working in `web/` (decision 18 in `ROADMAP.md`). The plan, the
decisions and the open questions are in `ROADMAP.md`; the library's and
the workspace's notes in the root `CLAUDE.md`. The user docs are in
`README.md`, with the manual checklist (decision 14): when the UI
changes, keep its description, its table of the CLI's options and the
checklist in step.

## The package

- **Modules:** `Puregrain.Web.Main` (the page's entry: reads the theme
  from the system and the library's version, then mounts the app on the
  body), `Puregrain.Web.App` (the component: its actions and their
  effects), `Puregrain.Web.State` (the state and the actions),
  `Puregrain.Web.View.Header`, `.Column`, `.Stage` and `.Footer` (the
  page's parts, decision 29), `.Controls` (the settings' controls,
  decision 31: a numbered step, cards and segments, a stepper, a toggle
  switch, a note, a file chooser like a button), `.Parts` (a menu's
  option, the `inert` property, the project's links) and `.Icon`
  (inline SVG icons),
  `Puregrain.Web.Theme` (pure: the
  two themes, decision 32), `Puregrain.Web.Page` (the system's theme, the
  root's `data-theme`, the version's meta element, whether the layout
  is a phone's; FFI),
  `Puregrain.Web.Picture`
  (decoding and reading a picture with its transparency, exactly, drawing
  pixels; FFI in `Picture.js`), `Puregrain.Web.Prepare` (the
  background and the fit, decisions 22 and 27: the rules pure, the loops
  over a whole picture in `Prepare.js`, pinned to the rules by
  `PrepareSpec`), `Puregrain.Web.Estimate` (the time left, decision 23:
  pure, with the page's clock, `Effect.Now`),
  `Puregrain.Web.Status` (pure: the run's states, which picture shows,
  when the progress shows, the bar's note on the run; decision 30),
  `Puregrain.Web.Split` (pure: the split's handle, its drag and its keys;
  decision 31), `Puregrain.Web.Drag` (pure: counting a drag of files over
  the page; decision 30 D), `Puregrain.Web.Pointer` (the pointer's
  events for the handle; FFI), `Puregrain.Web.Download` (pure: the
  download's formats per target and size, and the format the button
  names; decision 31), `Puregrain.Web.Keys` (pure: the page's shortcuts
  and the zoom's keys; decision 33),
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
  only the worker's bundle holds those. `web/static/` holds `index.html`
  and `app.css`, our own stylesheet (decision 34): the page loads it and
  `app.js`, links the icons, and has a `puregrain-version` meta element
  that the build fills in. The icons and the lockups come from `logo/`,
  copied by the build: they're under the logo's own terms, not MIT, so
  none of them lives in `web/static/`.
- **Tests:** `web/test/`, `Test.Puregrain.Web.Main` listing the specs
  (`SettingsSpec`, `DitherSpec`, `DownloadSpec`, `DragSpec`,
  `EstimateSpec`, `KeysSpec`, `MessageSpec`, `PrepareSpec`, `RunSpec`,
  `SaveSpec`, `SplitSpec`, `StatusSpec`, `TextSpec`, `ThemeSpec`,
  `ZoomSpec`), run by
  `spago test` with the other suites, in Node, so
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
  dropped. While a run goes, the result before it stays on show
  (`keepsPrevious`, which is `resultShows` of the run it replaces;
  decision 30 B); the original shows for a picture's first run, after
  Cancel or a failure, and when the picture is prepared again (a new
  picture, target, fit or background). The progress shows once the run
  has gone on for a second (`progressDelay`), by a timer the run starts
  (`H.fork` with `delay`, dropped when `runs` has moved on), not at the
  next progress report: a large picture's first hundredth of the rows
  can take longer.
- **Loading** (decision 30 C): `loading` holds the file's name while it
  decodes, `notAPicture` the name of one that couldn't be, until the next
  load or setting (`restart` clears it). The picture shown and its run
  go on meanwhile, and stay for good if the file isn't a picture. The
  bar's middle has two fixed boxes, the run's and then the file's note,
  so both can show at once: a bad file during a run keeps the progress
  and × in sight.
- **The progress line keeps still** (the user's manual test): the bar
  first, then × (Cancel as an icon, "Cancel" for screen readers in
  hidden text, 24 × 24 pixels), then the text, so that only the text's
  end moves as it changes, and the time left before the rows: "Dithering:
  about 10 s left (465/1536 rows)", or "Dithering: 465/1536 rows" without
  an estimate. Tabular digits; while running, one line, cut with "…"
  rather than wrapped. Whether the text sits beside the bar or under it
  depends on the width alone: `.bar-state` is a size container, and
  under 36 rem the text goes under the bar for the whole run (a phone, a
  1024-pixel window), so it never jumps between one line and two; with a
  basis of 22 rem, the bar's middle takes a line of its own (the download
  going below) before it gets too narrow, and on phones always. Checked
  (`step66c_check.mjs`): over 103 changes of a 30-second run the bar and
  × never moved, nor the bar's height, which grows once when a bad file's
  note comes.
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
  finishes, before it's shown (over the result before it, if that one
  shows). Without a result to show it's hidden (the `hidden` property;
  see "`[hidden]` and our styles"), with the handle and the labels, and
  the download is unavailable. The result's `clip-path: inset(0 0 0
  X%)` cuts off its left part: X is the split in picture columns (0 to
  the width) as a share of the width, so the cut falls between screen
  pixels at every zoom and pixel ratio; the handle's `left` is the same
  X%, its 2-pixel line centered on the cut.
- **The split's handle** (decision 31; `Puregrain.Web.Split`): Halogen
  7.0.0 has no pointer events, so the handle takes `pointerdown`,
  `pointermove`, `pointerup` and `pointercancel` as plain events
  (`HE.handler (EventType …)`) and reads them through
  `Puregrain.Web.Pointer`'s few lines of JavaScript. A press of the main
  button captures the pointer (`setPointerCapture` on the handle, so the
  moves come also from outside it) and notes where it took hold,
  relative to the line, so the line doesn't jump to the pointer; each
  move puts the split on the nearest column boundary. A move with no
  button held ends a drag whose release went elsewhere. Only the handle
  has `touch-action: none`: a touch elsewhere still scrolls the picture.
  The keys come through `HE.onKeyDown` (`web-uievents`), and a key the
  handle uses is `preventDefault`ed, so End doesn't also scroll; ↑ and ↓
  and the keys with Ctrl, Alt or Meta stay the browser's. A
  `role="slider"` with `aria-valuetext` "column 160 of 320".
- **The download** (decision 31; `Puregrain.Web.Download`): one button
  naming its format, and for a machine ▾ beside it, which shows a list of
  the formats (a disclosure, decision 34: `aria-expanded` and
  `aria-controls`, a list of buttons). An impossible format is only
  `aria-disabled`, so Tab still reaches it and its reason. Choosing one
  downloads it and makes it the button's format (`format`, kept for the
  visit); the button falls back to PNG while it isn't possible. Escape
  and a click outside close the list, the focus going back to ▾; the
  click is outside when the download's box doesn't `contains` its target
  (`web-dom`'s `Node.contains`, through a click listener on the
  window). A new run closes it (`restart`), so it can't come back open
  over a later result. On a phone's width, the download has a line of its
  own, and the list its width.
- **The shortcuts** (decision 33; `Puregrain.Web.Keys`): a `keydown`
  listener on the window. Ctrl or Cmd, on every system; the letter from
  the key's character when it's Latin, else from its place (`code`), so
  a Russian layout's Ctrl+щ is Ctrl+O. Ctrl+O clicks the column's file
  input (`chooserRef`): a key press is a user action, so the browser
  lets the page open its file chooser (checked in Firefox:
  `navigator.userActivation.isActive` is true in that `keydown`, and the
  console shows no "picker was blocked", also with the column hidden).
  Ctrl+S is taken even with nothing to download, so "Save page as" never
  opens over the page. Esc closes the list of formats if it's open, else
  cancels a run. + (and =) and − zoom while the picture area has the
  focus: `.view` has `tabindex="0"` and its own `keydown`, which the
  handle's keys bubble to; its focus ring is drawn inside it
  (`outline-offset: -2px`).
- **The knob is sticky** (`position: sticky; top: calc(50% - 16px);
  bottom: calc(50% - 16px)` inside the handle, as tall as the picture),
  and sticky positions count from inside the scroll container's padding:
  with the view's 46 pixels above and 32 below, the knob sits 7 pixels
  below the middle of the visible area, which is where a picture that
  fits has its middle (it's centered in the same box).
- **Zoom in screen pixels:** the canvas's CSS size is the picture's size
  × zoom ÷ `devicePixelRatio`, so each picture pixel is exactly zoom ×
  zoom screen pixels, also at fractional ratios (1.25, 1.5 on many
  laptops). A whole-number scale stays exact whatever the canvas's
  offset: checked at ratio 1.5 with a 1-pixel checkerboard in Firefox's
  screen-pixel screenshot (squares exactly 1 and 2 screen pixels at 1×
  and 2×, phase 2). The browser's zoom changes the ratio and fires
  `resize`, which the app listens to.
- **Build:** `npm run web:build` (`web/build.mjs`) clears `web/dist/`,
  bundles the page into `web/dist/app.js` and the worker into
  `web/dist/worker.js`, minified, copies `web/static/`, the logo's three
  icons, its two lockups and its two marks (`logo/zx/`, `logo/c64/`)
  next to them, and
  writes the library's version, read from the root `spago.yaml`
  (`publish.version`), into `index.html`'s meta element, for the
  footer; a version written there keeps `npm run check` independent of
  the web build, unlike a generated source file.
  `web/dist/` is gitignored. `npm run web:serve` serves it on
  http://localhost:8000; stop it with Ctrl+C.
- **Sizes** after v2's phase 6: `app.js` 173.6 KB, 43.3 KB gzipped
  (77.9 KB, 19.1 KB gzipped after v1's phase 1: mostly Halogen; 137.0
  KB, 34.2 KB after v2's phase 3; 155.5 KB, 39.3 KB after v2's phase 6,
  step 3); `worker.js` 71.2 KB, 18.8 KB gzipped, with the library (since
  v1's phase 3) and the machines' modules; `app.css` 22.8 KB, 6.4 KB
  gzipped, in place of Pico's 11.7 KB. Gzipped at gzip's
  default level (`gzip -c`); the worker's 18.6 KB noted before was at
  level 9. PureScript's output is wordy before minifying: a module of a
  few lines, `Download`, is 3.5 KB in an unminified bundle; `spago
  bundle` without `--minify` marks each module (`// output/…`), which
  shows where the bytes go.
- **The column's slide** (decision 29): the column keeps its 340 pixels
  and moves left by them (`transform`) while its grid track narrows to
  nothing (`grid-template-columns` animates in Chrome 107, Firefox 66,
  Safari 16), so it slides out; after the 200 ms it's `visibility:
  hidden`, which takes it out of the Tab order and from screen readers.
  The tab is placed absolutely, out of the grid. On a phone's width the
  column is the settings' panel, which slides in and out the same way.
- **The phone's panel** (decisions 29 and 34): the settings' column
  itself, under 760 pixels a fixed box over the whole screen, opened by
  the header's settings button (shown on phones, with a picture). Closed,
  it's off the screen and `visibility: hidden`, as the desktop's hidden
  column. Open (`.app.panel-open`), it's a modal dialog (`role`,
  `aria-modal`, and `tabindex="-1"` to take the focus), and the header,
  the picture area, the footer and the column's tab are `inert`. Apply
  sits in a sticky bar at its bottom, shown on phones only. Opening it
  pushes a step onto the history; the browser's back (`popstate`) closes
  it, and the other ways of closing (Apply, Esc, the window growing past
  760 pixels, read by `matchMedia` at each `resize`) go back a step
  themselves, `popstate` then finding it closed. Every close applies:
  while it's open, `restart` holds the run (`Held`, which keeps
  showing what the run before it showed, `Puregrain.Web.Status.held`),
  stopping a running worker; the held run starts when it closes. The
  focus goes into the panel and back to the settings button. A known
  edge: reopening it in the moment between Apply and the history's step
  going back would close it again. The column is a `div` with
  `role="complementary"`, which is what `aside` means, since an `aside`
  may not take the dialog's role (axe-core's `aria-allowed-role`).
- **Accessibility** (decision 33; checked with axe-core, see below):
  - The page's heading is the header's lockup and "lab", an `<h1>`
    named "puregrain lab".
  - **Skip links**, "Skip to the settings" and "Skip to the picture",
    first in the page, out of sight until the keyboard reaches them; a
    click moves the focus to the column or to `main#picture` (both
    `tabindex="-1"`, their focus ring drawn inside them), without
    changing the page's address. The one to the settings is hidden while
    the column is, and on phones, where the header's button opens them.
  - **Two live regions** at the page's end, outside every part that can
    turn `inert`: a `role="status"` for the run's milestones ("Dithering…"
    once the progress shows, "Done: 4 levels, Atkinson.", "Cancelled; the
    original is shown."), and a `role="alert"` for errors (a file that
    isn't a picture, a failed run, a PNG not made). Not the bar: it
    changes with every step of the progress. The same words said twice
    would leave a region unchanged, and unheard, so every other time a
    no-break space follows them (`Said`'s `times`).
  - **The pictures** are `role="img"` with names: "The original:
    plain.png", and the result's, "The result: 4 levels, Atkinson", in
    the menus' words (`texts.describe`). The result's name is kept in
    the state (`resultLabel`) from when it was made, so that during the
    next run it still names what's shown.
  - **Contrast,** measured from the themes' own values: text 4.5:1 and
    more (the lowest, muted text on the light picture area, 4.89); the
    controls' outlines 3:1 against what's behind them (3.07 dark, 3.04
    light, on the panels). The column's tab, half over the picture area,
    whose gray is too close to the light theme's outline (2.36), has a
    stronger border, the muted text's color.
  - **The focus** (the user's manual test, decided with them): on a
    desktop the empty page starts with it on step 1's "Choose a
    picture…", so Enter opens the file chooser; the skip links come
    before it, reached with Shift+Tab, and on a phone, where the settings
    are hidden, nothing has it. The first picture takes away the button
    that had it (step 1's buttons change, and Halogen, matching children
    by position, replaces them; the drop zone goes): unhandled, the focus
    fell to the page and the next Tab went on from the picture area. Now
    it goes to the next step, the chosen target, or on a phone to the
    Settings button (`Puregrain.Web.Keys.focusAfterLoad`). A later
    picture leaves it on "Choose another…", which keeps its place, so
    several pictures can be tried with the same settings. Each picture is
    announced: "Loaded: plain.png, 320 × 200 pixels."
  - **Targets:** everything clicked is 24 × 24 pixels or more, except the
    header's and the footer's links (18 to 20 pixels tall), which WCAG
    2.2's spacing exception covers: a 24-pixel circle on each meets no
    other target.
- **The threshold's slider** shows its value while dragged (`input`,
  `ThresholdDragged`: the number follows) and starts a run only when
  released (`change`, `ThresholdTyped`; decision 31).
- **A file chooser like a button:** a `<label>` around the file input,
  which is visually hidden but keeps the focus and the keys; Marionette's
  `ElementSendKeys` still chooses a file through it.
- **The theme comes before the first render:** `Main` reads the
  system's setting and puts `data-theme` on the page's root, then passes
  the theme to the component as its input, because Halogen runs a
  component's initializer after its first render: read there, a dark
  system would see the light theme's logo first. Before the app runs,
  the stylesheet follows `prefers-color-scheme`, so the dark values are
  written twice, in that media query and under `[data-theme="dark"]`.
- **`[hidden]` and our styles:** a browser hides `[hidden]` elements by
  its own stylesheet only, and any `display` of ours wins over it: the
  canvases' `display: block` would show the hidden result. `app.css` has
  `[hidden] { display: none !important; }` (Pico had it before).
- **SVG in Halogen** (7.0.0): `HH.elementNS (HH.Namespace
  "http://www.w3.org/2000/svg") (HH.ElemName "svg")`, its attributes with
  `HP.attr (HH.AttrName "viewBox")`; see `View.Icon`.
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
- **Pico CSS** (`@picocss/pico` 2.1.1, MIT, 83 KB, 11.7 KB gzipped)
  styled v1 and v2's phases 1 to 4; our own stylesheet replaced it in v2's
  phase 6, step 1 (decision 34), and it left the dependencies.

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
- **Drops:** the whole page (`.app`) takes them, so that a drop beside
  the picture doesn't make the browser open the file; `dragover` must
  call `preventDefault`, or the browser refuses the drop. For the drop
  zone's light and the overlay (decision 30 D), the page counts the
  `dragenter` and `dragleave` of drags whose `types` hold "Files"
  (readable while the drag goes on, unlike the files); a drop sets the
  count to 0 (`Puregrain.Web.Drag`). The overlay has `pointer-events:
  none`, so the drag's events reach the elements under it, and the
  picture area is a stacking context of its own (`isolation: isolate`),
  so the overlay stays under the column's tab.
- **An element removed while a drag is over it** gets its `dragleave`
  detached from the page, so the event never reaches the page's
  listener, and the count would stay up, the overlay with it, until the
  next drop. So the parts that change under a pointer are hidden rather
  than removed: the canvases, the handle, the labels, the overlay, and
  the bar's notes, progress and Cancel, which go when a run ends. The
  empty area does go when the first picture loads, after its drop.
- **Halogen matches unkeyed children by position.** When an element
  before the canvas comes or goes (the progress bar, say), the canvas is
  rebuilt as a new, blank element, and drawing through the old reference
  misses it: phase 3's first browser check read a blank canvas. Parts
  whose elements come and go are hidden rather than removed, or sit in
  fixed containers (the bar's `.bar-file` and `.bar-run`), so the
  canvas keeps its place.
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
- **Icons:** linked as Evil Martians' "How to Favicon" recommends: the
  ICO with `sizes="32x32"`, since Chrome otherwise takes it over the SVG,
  then `icon.svg`, then the 180 × 180 `apple-touch-icon.png`, with
  relative paths, since Pages serves the site below `/puregrain/`.
  Every target browser takes the SVG for the tab (caniuse, 2026-10-26:
  Chrome and Edge since 80, Firefox since 41, Safari since 26; served as
  `image/svg+xml`, which caniuse notes is required), so the ICO serves
  older browsers and tools that read only `favicon.ico`. Firefox's tab
  takes the SVG (checked in v2's phase 4). An `<img>` of the ICO shows
  its largest entry, and `#-moz-resolution` doesn't choose another
  there.

## Facts for v2's design (checked 2026-10-31)

For the technical choices of v2's phase 5 (decision 34 in
`ROADMAP.md`).

- **Support,** from MDN's browser-compat-data 8.1.7 (2026-10-22), the
  first full version in Chrome, Edge, Firefox, Safari: container queries
  105, 105, 110, 16; `:has()` 105, 105, 121, 15.4; `color-mix()` 111,
  111, 113, 16.2; `inert` 102, 102, 112, 15.5; `<dialog>` with
  `showModal()` 37, 79, 98, 15.4; `popover` 114, 114, 125, 17;
  `setPointerCapture` 55, 12, 59, 13; `position: sticky` 56, 16, 32, 13;
  `prefers-color-scheme` 76, 79, 67, 12.1; `prefers-reduced-motion` 74,
  79, 63, 10.1; `color-scheme` 81, 81, 96, 13; `:focus-visible` 86, 86,
  85, 15.4; `navigator.clipboard.writeText` 66, 79, 63, 13.1. Recent in
  Safari: `accent-color` and `scrollbar-color`, 26.2. Anchor
  positioning: `anchor()` 125, 125, 147, 26, but `position-anchor` in
  full only 151, 151, 151, 27. The current versions then: Chrome 156,
  Edge 155, Firefox 158, Safari 27.
- **Sizes:** the design mockup's styles 11.5 KB minified, 3.1 KB
  gzipped; Pico CSS 83.3 KB, 11.6 KB gzipped. The logo's lockup 2.9 KB
  (ZX) and 4.6 KB (C64) as PNG at 1×, 33 KB as SVG (6.2 KB gzipped).
- **Checked in headless Firefox** (157):
  - a knob with `position: sticky; top: calc(50% - 16px)` inside an
    absolutely placed handle as tall as the picture stays in the middle
    of the scrolling area's visible part at every scroll position, and at
    the picture's middle when it fits;
  - Ctrl+S and Ctrl+O reach the page, which can take them over:
    `preventDefault` holds and the page stays;
  - a button inside an `inert` part can't take the focus, and can once
    `inert` is lifted.

## Checking in a real browser

**`npm run check:web`** (decision 25, 2026-11-01): `scripts/check-web.mjs`
drives Chromium, Firefox and WebKit through Playwright (`playwright-core`,
a dev dependency: Apache-2.0, no dependencies, no install script). Only
the browsers run in Docker; the CLI, the references and the comparisons
stay on the host.

- **The container:** `mcr.microsoft.com/playwright:v<version>-noble`, the
  version read from the installed `playwright-core`, so the two can't
  drift. Run with `--init --ipc=host --user pwuser`, as Playwright's
  Docker page advises. `scripts/lib/check-web-container.mjs`, mounted
  read-only with `web/dist` and the host's `playwright-core`, runs under
  the image's Node (24): it serves the page at `http://localhost:8080/`
  inside the container, then starts the CLI's hidden `run-server`
  command (not listed by `--help`) on port 3000. That port is published
  on 127.0.0.1 at a port Docker picks (`--publish 127.0.0.1::3000`, read
  back with `docker port`); the check waits for "Listening on" in
  `docker logs`, then calls `connect` for each engine.
- **Why the page is served inside:** a local address is a secure
  context, as GitHub Pages is, and the browsers reach nothing on the
  host (no host network, no `host-gateway`); the page uses no
  secure-context API today, so this is for faithfulness.
- **Files cross Playwright's connection:** `setInputFiles` with a local
  path uploads the file to the remote browser; `download.saveAs` brings a
  download back (`download.path()` isn't available remotely).
- **Waiting for a run:** an init script wraps `window.Worker` and counts
  the runs, noting each one's first answer that isn't progress; the
  check waits for a new run's answer, then for the page's finished state
  (the download button enabled, no progress). The download's name,
  which carries the settings, confirms which result it is.
- **The controls:** `selectOption` on the two menus (colors, then
  kernel), `fill` on the levels' number, and the radio buttons
  (segments and cards) clicked in the page once enabled. The split is
  set by keys on the handle (Home, Shift+→ for tens, → for ones), the
  handle and the labels hidden by a style tag for the screenshot, at
  device pixel ratio 1, with the canvas's corner tried ±1 screen pixel.
- **First results (2026-11-01):** all 48 checks pass in Chromium 156,
  Firefox 157 and WebKit 27.2, in 31 s once the image is there (its
  download took 54 s here; 2.54 GB on disk). Mutation-checked: wrong
  references (30 checks failed, as predicted), the split's sides swapped
  (18), and a bug in the built page, one of Atkinson's weights 1/8 → 1/9
  in `web/dist/worker.js` (the Atkinson result and 5 of the 6 splits
  failed in each engine; at column 320 only the original shows). Ctrl+C
  removes the container.

Ad hoc, phases 1 to 6 were checked without Playwright (decision 14): the
system's Firefox, headless, driven through Marionette, its built-in
remote control (length-prefixed JSON over TCP, port 2828), by a few
lines of Python from the standard library (phases 1 to 3) or of Node
(phase 4: a client of about 40 lines on `node:net`, with pngjs reading
screenshots and downloads). Phase 1's check loaded the page and read
"The worker answered: ping" from it.

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
  `WebDriver:PerformActions` sends real input, through the browser's
  own path: a mouse's moves, presses and releases (the page gets
  pointer events with a real `pointerId`, so capturing works), and keys
  (`\uE014` for →, `\uE008` for Shift, `\uE010` End, `\uE011` Home);
  `WebDriver:ReleaseActions` afterwards. `WebDriver:Back` goes back in
  the history as the browser's button does, `popstate` included. A file
  for a synthetic drop can be fetched in the page
  (`WebDriver:ExecuteAsyncScript`) from the check's own server. A hidden
  element's `innerText` is its `textContent`, hidden parts included,
  while text under `visibility: hidden` (the closed phone panel's) is
  left out of a shown element's `innerText`: a check reads such text
  with `textContent`. A check can count the runs by wrapping
  `window.Worker`, which the page calls for each. With `devtools.console.stdout.content` in `user.js`,
  Firefox writes the page's console to its standard output, where the
  check script can read it (a file chooser refused for lack of a user
  action says "picker was blocked"). After the page's last stop, Tab
  takes the focus out of the page (headless Firefox has no toolbar to
  take it), and it comes back without `:focus-visible`: a Tab walk stops
  where the focus reaches the `body`. axe-core is run by injecting its
  `axe.min.js` (installed in the scratchpad, not a dependency) with
  `WebDriver:ExecuteScript` and calling `axe.run` with
  `WebDriver:ExecuteAsyncScript`.
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
- **Checked in v2's phase 3:** a 4096 × 3072 picture, Floyd–Steinberg
  with a threshold, ran 31 s in headless Firefox: the time left showed
  from 2.2 s ("about 30 s left", 29 s actually left), stayed to the end,
  and was within 20% of the time actually left whenever more than 10 s
  were. A 320 × 200 picture showed none.
- **Checked in v2's phase 4:** the page links the three icons and serves
  them as in `logo/`; Firefox draws each of the logo's SVGs exactly as
  its PNG, at 1 and 4 times (`icon.svg` as the ICO's 16, at 1 and 2
  times), decodes each of the ICO's three bitmaps exactly (each served as
  an ICO of its own), and its tab takes `icon.svg`.
- **Checked in v2's phase 6, step 1,** on the new skeleton: the split
  exact to the screen pixel at ratio 1 (1× at splits 160, 0, 320, 1, 37
  and 319; 3×) and 1.5 (1× and 2×), the picture centered in its area (at
  x = 863.33 CSS pixels at 1.5); the downloads the CLI's (two PNGs, and a
  ZX Spectrum screen's PNG and `.scr`, byte for byte); Cancel; the theme
  from the system at load, dark and light, the switch, and the logo's
  set; only `app.css` loaded; the footer's versions; on a phone's width,
  the picture above the settings, without sideways scrolling.
- **Checked in v2's phase 6, step 2,** through the column's new
  controls: the empty page's steps after the first disabled; the levels'
  stepper (− disabled at 2, + at 256); the threshold's slider (no run
  while dragged, the number following, a run on release, the CLI's
  pixels at 100); the toggle switch (`role="switch"`, the CLI's `--gray`);
  the Bayer segments disabled with a palette, with the note; the ZX
  Spectrum through its card and "Use 8×8", its screen and `.scr` the
  CLI's; the fit's note on a 512 × 512 poster; the « / » tab (the
  column hidden, a setting unable to take the focus, the picture's area
  the window's width, the split still exact; open again); with the
  system's animations off (`ui.prefersReducedMotion` 1 in `user.js`),
  no transition and the column hidden at once; on a phone's width, no
  tab and the settings shown.
- **Checked in v2's phase 6, step 3** (`step63_check.mjs`): the empty
  area (the drop zone, the mark in each theme's set, both "Choose a
  picture…", the texts); a file that isn't a picture, above the drop
  zone, and with a picture shown, in the bar, the picture and its result
  kept (also during a run, the progress going on); "Loading plain.png…"
  on the way; a drag of files lighting the drop zone and, over a
  picture, the overlay, counted through a child, not for a drag of
  text, the column's tab above it (0 of its 612 screen pixels changed;
  306 without the stacking context), and a drop that loads; the handle
  dragged by the mouse (taken hold 6 pixels off the line: no jump; out
  of the picture: captured, to 0 and to the width; a drag beside it
  moves nothing), by the keys (← →, with Shift, Home, End, at the edges;
  End, Home and → don't scroll, ↓ does), `role="slider"` with its value
  text; the split exact to the screen pixel after it at ratio 1 (1× and
  3×) and 1.5 (1× and 2×, a 40-pixel drag there 30 columns); the knob on
  the line, at the middle of a picture that fits, and of the area inside
  the view's margins on a tall one at every scroll position; the labels
  above the corners, side by side over a 96-pixel picture; a short run
  without progress, a long one keeping the result before it, its
  progress after 1.06 s, then Cancel showing the original, and the next
  run too; the zoom's segments; the downloads the CLI's (a PNG, and a ZX
  Spectrum screen's PNG and `.scr`, byte for byte); a phone's width
  without sideways scrolling, the knob 40 pixels, the handle 44.
- **Checked in v2's phase 6, step 4** (`step64_check.mjs`): the download
  button, "Download PNG" with no ▾ for any screen, unavailable until a
  result; for the ZX Spectrum and the C64, ▾ (`aria-expanded`,
  "More formats") and the list, each entry with its file's name; every
  format through the list, and the button's format through the button
  and Ctrl+S, byte for byte the CLI's (`.scr`, `.tap`, `.prg`, `.art`)
  or its pixels (the PNGs); the button taking the format chosen, PNG for
  any screen, for a poster and for the other machine, and the format
  again back on the screen's size; a poster's `.scr` and `.tap` saying
  "needs a 256 × 192 picture", choosing one saving nothing; Esc closing
  the list with the focus back on ▾ and the result kept, a click outside
  and ▾ closing it; during a run the button unavailable and Ctrl+S
  saving nothing, Esc cancelling, and Esc with nothing to cancel
  changing nothing; Ctrl+O opening the file chooser from a user action,
  on the empty page and with the column hidden, the page staying; + and
  = and − in the picture area, at its ends and through the handle; the
  tooltips; at ratio 1.5, the list and a `.scr`; on a phone's width, the
  list within the screen.
- **Checked in v2's phase 6, step 5** (`step65_check.mjs`, at a phone's
  width): no settings button on the empty page, the panel off the
  screen, the short tagline; with a picture, the button ("Settings",
  `aria-expanded`); the panel over the whole screen, a modal dialog with
  the focus, the rest inert (the theme switch can't take the focus), a
  step in the history, Apply at the screen's bottom; changes starting no
  run (no worker made) until Apply, then one, the CLI's pixels, the focus
  back on the button and the history's step gone; Esc and Back closing it
  the same way, the result before shown meanwhile, the page staying; no
  run without a change; another picture chosen in the panel, its run
  held; the window widened while open: the panel closed, the held run
  started, the column beside the picture; at a desktop's width a change
  running at once; with animations off, no slide.
- **Checked in v2's phase 6, step 6** (`step66_check.mjs`): axe-core
  4.14.0 (WCAG 2.2 A and AA, and its best practices) finding nothing on
  the empty page, a picture at none, a result, the list of formats open,
  a run, a bad file's note, in both themes, and on a phone with the
  panel closed and open (first it found the missing `<h1>` and the
  dialog's role on an `aside`); the empty page's focus on "Choose a
  picture…" on a desktop, two Shift+Tabs from it reaching the theme
  switch and six the first skip link, none on a phone; the first
  picture, chosen or dropped, moving the focus to the chosen target (on
  a phone to the Settings button), a later one leaving it on "Choose
  another…", each announced; Tab from the first skip link through 23
  stops, in reading order (skip links, header, the column's tab, column,
  picture, bar, footer), each with a focus ring of 2 pixels; the skip
  links moving the focus without changing the address, only "Skip to the
  picture" on a phone, there on the first Tab; the pictures' names;
  what the regions said: only "Done: 4 levels, Atkinson." for a short
  run, "Dithering…" for a long one, "Cancelled" twice changing the
  region twice, an error at once; the targets and the contrast as above;
  nothing moving with animations off, at a desktop's and a phone's
  width, `::before` and `::after` included. The checks of steps 3, 4
  and 5 run again, all passing (the split still exact to the screen
  pixel).
- **A headless Firefox window is at least 500 pixels wide:** asked for
  390, it gave 500, still a phone's layout here (under 760). In a
  profile's `user.js`, `layout.css.prefers-color-scheme.content-override`
  0 or 1 (with `ui.systemUsesDarkTheme` 1 or 0) gives the page a dark or
  a light system.
- **The browser's own UI** (a tab's icon, say) is Marionette's chrome
  context (`Marionette:SetContext`), which needs Firefox started with
  `-remote-allow-system-access`.
- **Start the check's Firefox from the check script** (Node's `spawn`)
  and end that process: `pkill -f` with the profile's path also matched
  the shell running it, whose command line holds the same path, and
  ended it mid-check (phase 4).
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
