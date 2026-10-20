# Web UI: roadmap

The working document of the web UI: the vision, decisions, open
questions, versions, phases and progress. The work spans several
versions on the long-term branch `web-ui` (decision 13), so the file
lives with its package in `web/`. At the merge, user docs go to their
permanent homes and decisions, with their reasons, to `CLAUDE.md` (see
Q12).

## Goal

A web UI for the library: its second real client, after the CLI. It
should be useful on its own, and it should shape and verify the library's
PureScript API from a new side: in a browser, interactive, row by row
with progress and cancelling. (The JavaScript/TypeScript API for npm
users is a separate task, see TODO.md.)

### The long-term vision (theses)

- **Input:** choose a picture, by upload or drag and drop.
- **Settings:** the dithering method and its parameters and presets.
- **Retro:** the machines (`zx-spectrum`, `c64-hires`) and their
  properties.
- **Viewing and comparing:** the result and the original side by side, or
  in one box with a vertical split slider; magnified with sharp pixels,
  pan synchronized between the views. Keep several results (5 to 10) and
  compare them with each other the same way.
- **Output:** save as an image, and as the machine's own file when a
  machine was chosen.
- **Long runs:** a progress indicator and cancelling.

## Versions

- **v1, the spike:** set up the web project; load a picture; basic
  settings; one picture with its result; progress and cancelling; PNG
  download. Functional, not yet styled. Detailed below.
- **v2:** the machines, with their files as downloads; the design, the
  look and feel (a review of CSS frameworks, animations); an estimate of
  the total time after the first rows.
- **v3:** several results kept and compared; magnifying with synchronized
  pan; side by side.
- **The pull request** comes when the UI is ready to present: functional,
  styled and hosted on GitHub (decision 13; the hosting is the user's
  decision, since it publishes).
- **Later:** see "Later ideas".

## Decisions

1. **A long-term branch `web-ui`, with this file** (2026-10-19, the
   user's proposal). Short-lived branches may be cut from `master` or
   from `web-ui`, when useful, not as a rule, and merge back into the
   branch they came from by pull request. To be written into
   CONTRIBUTING.md, with decision 13.
2. **PureScript with Halogen,** the standard PureScript UI library, in
   the Elm style (2026-10-19). A PureScript client doesn't test the
   JavaScript API; that stays the npm task's.
3. **In this repository, as the workspace package in `web/`** (2026-10-19):
   a library change the UI needs is one build away, and CI compiles the
   UI with everything else, so an API change that breaks it fails CI. It
   can move to a repository of its own later. Built into static files;
   run locally first.
4. **v1 writes PNG only;** the machines and their files come in v2.
5. **v1 is functional; the design comes in v2.**
6. **Progress and cancelling from v1 on.**
7. **The settings as in the CLI** (Q1, 2026-10-19): two axes, *colors*
   (a gray threshold, levels, a palette; a machine in v2) and *method* (a
   kernel, a Bayer map, or both combined). The CLI's rules carry over: no
   Bayer map with a palette or a threshold; gray processing for an
   all-neutral picture or when asked for.
8. **Pico CSS for v1** (Q2): no JavaScript, no build step, plain HTML
   controls styled. The frameworks for v2 are reviewed later.
9. **The input** (Q3): the browser decodes the picture (PNG, JPEG, GIF,
   WebP, BMP); its color-profile conversion is turned off, so the stored
   values are dithered, as in the CLI. Transparent parts are put onto
   white; a configurable color, or one from the page's theme, may come
   later.
10. **No size limit and no warning in v1** (Q4): the progress indicator
    shows how long it takes. An estimate of the total time after the
    first rows comes later (v2).
11. **Cancelling ends the worker** (Q5): the worker runs a plain loop over
    the rows with the library's stepper and reports progress; cancelling
    ends it, and a new run starts a new worker. No coroutines.
12. **Names in a table of the web package** (Q6): decide after v1, with
    two clients side by side, whether the library should offer named
    presets. The web UI shows labels, not CLI names, and may one day show
    them translated: i18n isn't planned, but all the UI's texts stay in
    one module, so it stays possible.
13. **One branch, one merge** (Q7, 2026-10-19, the user's model): the web
    UI is developed on `web-ui` through its versions, until it's ready to
    present to users: functional, styled and hosted. Then it goes into
    `master` by one pull request, and the branch is deleted; a later
    stage would get a new branch from `master`. The versions are
    milestones on the branch, not merges. No short-lived branches for
    now; if one is needed, it merges back into its branch by pull
    request and is deleted. Since no branch carries on after its merge,
    squash merges cause no conflicts. Changes on `master` meanwhile come
    into the branch by a rebase or a merge of `master`.
14. **Testing** (Q8): thin components; the logic (settings to library
    calls, valid combinations, the state's changes on each action) in
    pure functions with specs, run in Node like the other suites; a
    short manual checklist for the rest. Headless-browser tests are a
    later decision.
15. **The split slider is our own** (Q9): two canvases stacked in one
    box, the top one cut at the slider's position with CSS; in v1 a
    plain range input sets the position. A handle dragged on the picture,
    or components from Web Awesome, belong to v2's design review.
16. **Dithering starts by itself** (Q10, the user's design): after a
    picture is loaded, every setting starts at a "none" value, labelled
    as such, and the page shows the original. The first change of a
    setting starts dithering with the settings as they are, and every
    later change cancels the run and starts a new one; no "Dither"
    button. One rule follows (Claude's addition, for phase 3): when a
    method is chosen while the colors are still "none", the colors take
    the CLI's default, a gray threshold at 128, so there's something to
    dither with.
17. **Browsers** (Q11): current desktop versions of Chrome, Firefox,
    Safari and Edge; phones on a best-effort basis.
18. **A `CLAUDE.md` in `web/`** (Q12, 2026-10-19): Claude Code reads a
    subdirectory's `CLAUDE.md` when it works on files there, not in every
    session, so the web package's gotchas and architecture go there,
    created with phase 0's facts; the root `CLAUDE.md` gets a short entry
    for the package with a pointer, in phase 1. Decisions that change
    the library (named presets, say) still go to the root.
19. **A self-contained static site** (2026-10-20): everything the page
    loads comes from our own build, served from one origin; no CDN. Our
    code (the library, Halogen, the app) is bundled by esbuild into the
    two scripts, which keep only the code used; third-party JavaScript
    (anime.js later, say) is imported from npm and bundled the same way;
    stylesheets and fonts are copied from their npm packages at build
    time, Pico CSS first. Why: a worker's script must come from the
    page's own origin anyway; browsers keep a separate HTTP cache per site
    since 2020–21 (Chrome 86, Firefox 85, Safari earlier), so a public
    CDN's copy is no longer shared between sites; a CDN sees every
    visitor's IP address, personal data in the EU; no outage or changed
    file elsewhere, exact versions from the lockfile, and it works
    offline locally. The cost, serving the bytes ourselves, is small:
    Pico is 11.7 KB gzipped, and the bundles are measured in phase 1.

## v1 in detail (draft, to settle)

- **Project:** a workspace package `puregrain-web` in `web/`, modules
  `Puregrain.Web.*`. Its dependencies (Halogen, the browser APIs) never
  reach the library. Scripts for a local build and a dev server.
- **Load:** file picker and drag and drop; decoding as in decision 9.
- **Settings:** as in decision 7.
- **Dithering:** in a Web Worker, so the page stays responsive, row by
  row with the library's stepper; progress after every few rows. A
  changed setting cancels the run and starts a new one (decisions 11,
  16).
- **View:** the original and the result in one box with a vertical split
  slider (decision 15), at whole-number zoom (1× to 4×) with sharp pixels: dither
  patterns blur or form moiré at any other scale. Both layers share the
  box, so they share zoom and scrolling.
- **Download:** the result as a PNG.
- **Tests:** as in decision 14.

## Phase 0 results (2026-10-20)

Everything v1 needs is available; the details, with their sources, are
in `web/CLAUDE.md`.

- **Packages:** our package set (81.4.0) has `halogen` 7.0.0, `web-html`,
  `web-file`, `web-uievents`, `web-workers`, `canvas`, `arraybuffer-types`,
  `aff` and `js-promise-aff`. A few lines of FFI fill the gaps:
  `createImageBitmap`, `toBlob`, an `ImageBitmap` as a canvas image.
- **Bundles:** two, made by `spago bundle --platform browser`, each a
  self-running script: the page's (`Puregrain.Web.Main`) and the
  worker's (`Puregrain.Web.Worker`, loaded as a classic worker). It needs
  esbuild as a dev dependency; its install script can be denied.
- **Serving:** a worker can't start from a page opened as a file, so
  even locally the page needs an HTTP server; esbuild serves a folder.
- **Browsers:** every API and CSS feature v1 uses works in current
  Chrome, Edge, Firefox and Safari: decoding without color conversion,
  workers and `terminate`, the canvas's pixel access, `toBlob`, drag and
  drop, the download link, `image-rendering: pixelated`, `clip-path`.
- **Pico CSS** 2.1.1 (MIT, no install script), copied into the build:
  11.7 KB gzipped.

### The data flow (design)

1. **Load:** the file (picked or dropped) is decoded with
   `createImageBitmap(file, { colorSpaceConversion: "none" })`, drawn onto
   a canvas filled white (decision 9), and read back with
   `getImageData`: the original's pixels, also shown on the page.
2. **Run:** on a change (decision 16), the page ends the running worker,
   if any, starts a new one, and sends it the settings as plain data, the
   size, and a copy of the pixels (transferred, not copied again).
3. **Worker:** turns the settings into library values (the same pure
   module the page uses to check them, as the CLI's `Pipeline`), dithers
   the rows one by one with the stepper (`initDithering`, `ditherRow`),
   writes each into the result's pixels, and reports progress every few
   rows; at the end it sends the result's pixels back (transferred).
4. **Show:** the page puts the result onto its canvas, under the split
   slider, and enables the PNG download (`toBlob`).
5. **Cancel:** the page ends the worker (decision 11).

The gray processing (an all-neutral picture, or gray asked for) needs the
CLI's `isNeutral` and `luma`, which live in the CLI's `Pipeline`: like
the names (decision 12), copied into the web package first, and a
candidate for the library after v1.

## Open questions

None at the moment.

## Later ideas

- An estimate of the total time, after the first rows (v2).
- The background color for transparent parts: configurable, or from the
  page's theme.
- Translations of the UI's texts.
- **A browser smoke test without Playwright,** for decision 14's later
  question: phase 1 was checked in the system's Firefox, headless, driven
  through its built-in remote control (Marionette) by a few lines of
  Python; see `web/CLAUDE.md`. No npm dependency. Whether GitHub's
  runners have a Firefox for it in CI is still to check.
- Keeping transparency (a question for the library and the CLI too, for
  TODO.md): the library has `RGBA` and dithers it per channel already,
  but palettes are RGB only, and the CLI ignores alpha. Transparency
  could be kept as on or off per pixel, for icons and sprites; the
  machines have none.

## Phases of v1 (draft)

0. **Verify and design, no code:** Halogen in our package set; `spago
   bundle` for the app and for the worker; how a worker loads the
   compiled code; the decoding options of decision 9 in each browser;
   the download.
   **Before phase 1:** the package set from 81.4.0 to 81.9.0 (2026-10-19;
   compiler 0.15.16, ours; small steps in 25 of our dependencies), as its
   own change on `master`, since it affects the library, the CLI and the
   examples: `npm run check:clean`, the CLI's outputs byte-identical, and
   a check that the workspace's own `puregrain` is used, not the set's
   0.2.0 of the same name. Then `web-ui` is rebased onto `master`.
1. **Setup:** the package (`web/spago.yaml`, `web/src/`, `web/static/`
   with `index.html`); an empty Halogen app and an echoing worker; esbuild
   and Pico CSS as dev dependencies (esbuild's install script denied);
   scripts to build into `web/dist/` (gitignored) and to serve it; the
   root `CLAUDE.md`'s entry; CI builds the package.
2. **Load and show:** picker and drag and drop, decoding, the picture at
   whole-number zoom.
3. **Settings and dithering:** the settings, the worker with the
   stepper, progress, cancelling.
4. **Compare and save:** the split slider, the PNG download.
5. **Delivery of v1:** user docs (`web/README.md`), `web/CLAUDE.md` and
   the root CLAUDE.md as far as they're due; the branch carries on
   (decision 13). CONTRIBUTING.md gets the branching rule (decisions 1
   and 13) with the pull request.

## Progress

- [x] 0. Verify and design
- [x] 1. Setup: the package, the two bundles, the dev server; checked in headless Firefox
- [ ] 2. Load and show
- [ ] 3. Settings and dithering
- [ ] 4. Compare and save
- [ ] 5. Delivery
