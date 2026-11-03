# Web UI: roadmap

The working document of the web UI: the vision, decisions, open
questions, versions, phases and progress. It lives with its package in
`web/`. v1 and v2 were developed on the long-lived branch `web-ui`
(decision 13), merged into `master` at the end of v2. The file stays
after the merge (decided 2026-11-01, instead of moving the decisions to
`web/CLAUDE.md` as first planned): the work goes on with v3, which
builds on these decisions, and `web/CLAUDE.md`, which Claude Code reads
every time it works in `web/`, keeps only the architecture and the
gotchas. The user docs are in `README.md`.

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
  download. Functional, not yet styled. Detailed below. Done on
  2026-10-21; its user docs are in `README.md`.
- **v2:** the machines, with their files as downloads; fitting a picture
  to the machine's screen; an estimate of the time left; the project's
  logo (decision 28); the design, the look and feel; at its end the
  merge into `master`, then the hosting and the checks on phones and in
  Safari and Chrome (decision 13). Planned on 2026-10-22: decisions 20
  to 26, and the phases below.
- **Between v2 and v3:** dithering in linear light, on `master` (TODO.md):
  the default, with a switch to turn it off, released as the library's
  0.3.0. The web UI then gets the switch too.
- **v3:** several results kept and compared; magnifying with synchronized
  pan; side by side. On a new branch from `master` (decision 20). From
  v2's design review (decisions 29 to 34): the gallery in a strip under
  the bar; "Start over" (back to the empty page, every setting at
  "none"), which clears the gallery, asking first when results aren't
  saved; an (i) next to each setting, opening a short description of it
  (the user's idea); a high-contrast theme (the user's idea); the zoom
  as a menu once there are more values. From the checks on devices
  (2026-11-03, the user's ideas): on phones, "Choose another picture"
  next to the download button, opening the file chooser at once and
  keeping the settings, as step 1's "Choose another…" does, which a
  phone hides in the settings' panel (not "Start over", which resets
  every setting; a phone has no drag and drop, so the empty page would
  only offer the same chooser); and a zoom of 0.5× at least, for
  pictures larger than the screen. Below 1× a screen pixel covers
  several picture pixels, so the dithering's pattern can't show as it
  is: an overview, to be marked as such.
- **The pull request** comes at the end of v2 (decision 20), when the UI
  is functional and styled; the hosting follows the merge, from `master`
  (decisions 13 and 26; switching Pages on is the user's, since it
  publishes).
- **Later:** see "Later ideas".

## Decisions

1. **A long-term branch `web-ui`, with this file** (2026-10-19, the
   user's proposal). Short-lived branches may be cut from `master` or
   from `web-ui`, when useful, not as a rule, and merge back into the
   branch they came from by pull request. Written into CONTRIBUTING.md
   in phase 7 as an exception, not as a general rule (the user,
   2026-11-01): the next long-lived branch may need another scenario,
   so its rules are decided with it.
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
   controls styled. The frameworks for v2 are reviewed later. In v2, our
   own stylesheet takes its place (decision 34).
9. **The input** (Q3): the browser decodes the picture (PNG, JPEG, GIF,
   WebP, BMP); its color-profile conversion is turned off, so the stored
   values are dithered, as in the CLI. Transparent parts are put onto
   white; a configurable color, or one from the page's theme, may come
   later (decision 27: a color of the user's choice).
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
    into the branch by a rebase or a merge of `master`. Changed
    2026-11-01 (the user's proposal): the merge comes before the hosting.
    With no users and no earlier version to break, the page is published
    from `master` after the merge, then checked on phones and in Safari
    and Chrome, with fixes on `master` (decision 26).
14. **Testing** (Q8): thin components; the logic (settings to library
    calls, valid combinations, the state's changes on each action) in
    pure functions with specs, run in Node like the other suites; a
    short manual checklist for the rest (`README.md`, "Checking a change
    by hand", since phase 5). Headless-browser tests are a later
    decision.
15. **The split slider is our own** (Q9): two canvases stacked in one
    box, the top one cut at the slider's position with CSS; in v1 a
    plain range input sets the position. A handle dragged on the picture,
    or components from Web Awesome, belong to v2's design review: there,
    a handle of our own, dragged on the picture (decision 31), and no
    component library (decision 34).
16. **Dithering starts by itself** (Q10, the user's design): after a
    picture is loaded, every setting starts at a "none" value, labelled
    as such, and the page shows the original. The first change of a
    setting starts dithering with the settings as they are, and every
    later change cancels the run and starts a new one; no "Dither"
    button. One rule follows (Claude's addition, for phase 3): when a
    method is chosen while the colors are still "none", the colors take
    the CLI's defaults: a gray threshold at 128, or 2 levels when a Bayer
    map is chosen (the CLI's `--bayer` alone), so there's something to
    dither with. "No Bayer map" and "gray first" aren't methods: with no
    colors, they leave the original. While a run goes, the original is
    shown; the result replaces it when it's done. Changed in v2: a new
    run keeps the previous result until the new one is ready (decision
    30, B), and on a phone a run starts when the settings close
    (decision 29).
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

Decisions for v2 (2026-10-22, from v2's questions Q1 to Q7):

20. **The merge after v2** (v2's Q1): with v2 the web UI is functional
    and styled, so `web-ui` goes into `master` by one pull request at the
    end of v2, and is hosted from there (decision 13's order since
    2026-11-01). v3 starts on a new branch from `master`, after
    dithering in linear light (see "Versions").
21. **Machine screens** (v2's Q2): both machines, the ZX Spectrum with its
    palettes full, normal and bright, and the C64's hires mode, with
    ordered dithering inside the cells, the kernels and gray first, as in
    the CLI. The result is a PNG; for a picture of the screen's size
    (256×192, 320×200) the machine's files too: `.scr` and `.tap`,
    `.prg` and `.art`. A machine with no method gives flat cells: a hint
    names the recommended method (ordered dithering, 8×8), and nothing is
    chosen by itself (decision 16). The tape's name follows the CLI's
    rule (the name without its extension, printable ASCII only, the
    first 10 characters), applied to the picture's name, since the
    download's is generated; `puregrain` when nothing printable is left.
    Progress comes after each band of cells, counted in the rows each
    band brings: no cell height is needed, and the last, partial band of
    a poster counts right.
22. **Fit to the screen** (v2's Q3): besides the CLI's rule (a PNG of any
    size, the machine's files only at the screen's size), the page
    offers to fit a picture to the machine's screen. Photos are far
    bigger than the screen: cropping alone would keep 0.4% of a
    12-megapixel photo. Settled for phase 2 (2026-10-25, with the user):
    - **Only with a machine as the target:** only a machine has a screen.
    - **One rule for every size:** scaled down, never up, so that it
      covers the screen as far as it can; centered; cropped where it
      overflows; the background color (decision 27) where it doesn't
      reach. A 6000 × 4000 photo becomes 288 × 192 and loses 16 columns
      on each side; a 100 × 80 icon stays as it is, the background around
      it. Enlarging isn't planned: no use case (the user).
    - **A checkbox in the size note,** off by default: unchecked, the
      picture is dithered as a poster, as by the CLI. Checked, the note
      says what was done (the user's idea).
    - **Our own scaling, not the browser's:** area averaging. Measured in
      Firefox (v2's phase 2): `drawImage` aliases badly at every
      smoothing quality, while the decoder's own high-quality resize is
      clean, but each browser has its own filter, and the CLI couldn't
      reproduce it. Ours is the same everywhere, and the CLI can get it
      with `--fit`; a sharper filter of our own could follow if needed.
    - **Download names** get `fit` when the picture is fitted.
23. **The time estimate** (v2's Q4, the user's design): time so far ÷
    rows done × rows left, from all the rows so far, updated with each
    progress message. Shown once the predicted total is over 10 s, the
    limit of attention in Jakob Nielsen's response-time limits
    (*Usability Engineering*, 1993): beyond it, users turn to other things
    and want to know when the computer expects to be done. Once shown, it
    stays until the end. As "about 40 s left" or "about 2 min 30 s left";
    the progress bar stays for every run. Rounded (phase 3): under a
    minute to the nearest 5 s, up to 10 minutes to the nearest 10 s,
    beyond to the nearest minute; "a few seconds left" at the end. The
    page's clock, from posting the job; checked in Firefox to within 20%
    of the time actually left.
24. **The design process** (v2's Q5, the user's): the logo first, in its
    own phase, since it can set the design's direction; then the screen's
    areas in text, sketches (as text, as HTML mockups, the user's as
    images), the components, and then the technical choices. Responsive,
    accessible (keyboard, labels, contrast), light and dark: today's
    standard. With a machine there are several downloads: a format menu
    next to the download button (the user's idea), settled in the design.
    Done in phase 5: decisions 29 to 34.
25. **A browser smoke test in v2** (v2's Q6): `npm run check:web`
    automates the checklist's exact parts: the CLI's pixels, the split,
    the downloads. Settled in phase 7 (2026-11-01): **Playwright**, as
    it covers the engines of all four target browsers (Chromium,
    Firefox, WebKit), where our own Marionette client has Firefox only
    and Puppeteer Chrome and Firefox. **Only the browsers run in a
    container**, Playwright's Docker image (the user's idea, a container;
    only the browsers, decided with the user): Playwright builds Firefox
    and WebKit for each Ubuntu version, so on the host this machine
    (22.04) and GitHub's runner (24.04) would test different builds; in
    one image they're the same, nothing for the browsers is installed on
    the host, and Docker was here already. The whole check in the
    container was weighed and left: its isolation is what CI already
    gives, a fresh machine on every run; locally it would rebuild from
    scratch each time, under the image's Node 24, neither this machine's
    nor CI's. `npm run check` runs it last, so it keeps running what CI
    runs, and needs Docker. CI runs it too; for `web-ui`, first on the
    delivery pull request, since CI runs on pushes to `master` and on
    pull requests only (the user's choice, 2026-11-01: no CI trigger for
    `web-ui`, and no early draft pull request). Details and gotchas:
    `web/CLAUDE.md`, "Checking in a real browser".
26. **Hosting on GitHub Pages** (v2's Q7): from `master` after the merge,
    built and deployed by a GitHub Actions workflow, at
    `https://roman-mkh.github.io/puregrain/`. **No visitor statistics**
    (the user's decision): Pages has none for a site (the repository's
    traffic page counts its pages on github.com), and an analytics script
    would break decision 19 and the README's privacy promise. Turning
    Pages on is the user's, since it publishes. Settled in phase 7
    (2026-11-01): a third job in `ci.yml` publishes from `master` only,
    once every check has passed, the very bundle `check:web` has just
    tested (an artifact of the checks' job), so a broken `master` can't
    replace a working page. No preview from `web-ui`: CI doesn't run
    there (decision 25), so a preview would publish unchecked bundles or
    need a trigger of its own; the checks on devices come after the
    merge, on the live page (decision 13). Checked before writing it: the
    page works under `/puregrain/`, all its paths being relative (served
    so to Chromium: every file found, no error, a download with the
    CLI's pixels).
27. **A background color for transparent parts** (2026-10-25, the user's
    proposal): one rule for both clients, transparent parts put onto a
    background color, white by default. The page offers a color picker
    (`<input type="color">`) for a picture with transparency; the CLI gets
    `--background RRGGBB`, a hex value as in CSS. The flattening is our
    own code, not the browser's compositing: color × alpha + background ×
    (1 − alpha), per channel, rounded; one formula for both clients,
    tested. For it the page needs the picture's exact RGBA, while a 2D
    canvas keeps colors premultiplied by alpha, which rounds
    semi-transparent ones. Settled for phase 2 (2026-10-25): the page
    reads a picture with transparency through WebGL, as a texture that
    isn't premultiplied, read back: exact in Firefox, where the 2D canvas
    was off by up to 254 at low alpha, our formula on its values by 1 in
    a third of the flattened values, and the browser's own compositing
    by 1 or 2 in about half of them. Without WebGL, the page falls back
    to the canvas values. The background is whatever lies behind the
    picture: under its transparent parts, and around a fitted picture
    that doesn't fill the screen (decision 22), so the color picker shows
    whenever the background shows. The page says so next to it (the
    user's idea). Download names get `bg-RRGGBB` when the background
    shows and isn't white. The page's part comes in phase 2, its formula
    a pure function of the web package; the library's helper and the
    CLI's flag come on `master` with linear light, before v3 (which
    decides whether to flatten in linear light), and the page then takes
    the library's helper, as planned for `luma`. Until then the clients
    differ on a picture with transparency: the CLI dithers the colors
    stored under transparent parts.
28. **The logo** (2026-10-25 and 26, phase 4, the user's choices from
    five rounds of candidates): made by puregrain itself, in `logo/` at
    the repository's root, with its own README.
    - **The shapes:** the mark, "Pg" in a pixel font, the capital P at the
      top left and the g at the bottom right sharing a corner (the bottom
      bar of the P's head runs into the g's top bar); the wordmark,
      "puregrain" in a 5 × 9 pixel font; the lockup, the mark beside the
      wordmark; and the swash, the P's stem sweeping into the g's tail, an
      extra for special and fun uses (the user's "anniversary addition").
      A dithered sphere and a grain were tried first: in color they looked
      like a basketball and a baseball (the user).
    - **Two equal color sets:** the ZX Spectrum's red to green with the
      4 × 4 Bayer map, and the C64's orange to blue with the 8 × 8 one. A
      gray gradient dithered by the CLI to two levels gives the dots: the
      dark ones take the first color, the light ones the second. First
      called primary and secondary, made equal on 2026-10-26 (the user's
      proposal): chosen by what fits the colors and style around them,
      with a recommendation, not a rule, from the colors' contrast: on
      dark backgrounds the ZX set, since the outline disappears there and
      the C64's blue fades (1.92 on GitHub's dark page, the ZX green 9.75;
      the table is in `logo/README.md`). The web icons and the social
      preview, which must work on any background, use the ZX set.
    - **A black outline around everything,** the holes included, so the
      logo stands on white, dark and transparent backgrounds (round 4;
      round 5's outline around the outside only was the alternative).
    - **The files:** SVG (a rectangle per run of a color: Firefox draws
      each exactly as its PNG, at 1 and 4 times), PNG at 1 and 4 times.
      For the web, in the ZX set: `favicon.ico` with 16, 32 and 48
      pixels (at 16 the strokes are 1 pixel wide and the gradient turned
      into noise, so the P and the g are flat red and green), `icon.svg`
      (the 16), a 180 × 180 `apple-touch-icon.png`, and the 1280 × 640
      `social-preview.png`, GitHub's link preview, which the user uploads
      in the repository's settings once the logo is on `master`. The page
      links the icons as Evil Martians' "How to Favicon" recommends;
      every target browser's tab takes the SVG (Safari since 26), so the
      ICO serves older browsers and tools.
    - **Its own terms, not MIT** (`logo/LICENSE.md`, the user's wish): the
      logo may be used unchanged to refer to puregrain, to show that a
      product uses it ("powered by puregrain"), and in copies of the
      repository used to work on it; not as the logo of a modified
      version, of a fork published as its own project, or of anything
      else. MIT would allow exactly those uses. The terms cover the whole
      folder, the script included, since it holds the design; the name
      stays out of them (the registries keep it unique). The root
      `LICENSE` stays plain MIT, so GitHub still shows "MIT" (it reads
      only the root); the README's License section names the exception.
    - **`npm run logo`** makes it again: the script gives every setting of
      the CLI, so a change of the defaults can't change the logo (for
      dithering in linear light, its opt-out goes into the script once
      the CLI has it), and it writes a file only when its pixels changed.
    - **In the root README** (phase 7, 2026-11-01, the user's choice):
      the ZX lockup as the README's heading, an SVG at twice its size,
      one picture for GitHub's light and dark pages and for Pursuit's
      light one, as the logo's README advises where one picture has to
      fit every background. Pursuit shows it: it rewrites a relative
      image path to `raw.githubusercontent.com` at the release's tag,
      which serves SVG as an image (checked). A `<picture>` with the C64
      set in light mode may be tried later from `master`; Pursuit would
      keep only its `<img>`, and whether GitHub takes relative paths in
      its `srcset` can only be seen once it's there.

Decisions of the design review (v2's phase 5, 2026-10-29 to 31): the
user's design (sketches and a concept) and Claude's (a concept and an
HTML mockup) were made separately, then compared goal by goal. Both stay
outside the repository (`samples/design-ram/`, `samples/design-claude/`);
these decisions are phase 6's reference (the user).

29. **The layout** (2026-10-30):
    - **Desktop:** the settings in a column left of the picture. A tab
      with a chevron on the column's right edge hides it («) and brings
      it back (»), so that the picture can take the whole width: for a
      large picture now, for side by side in v3. The tab doesn't look
      like the split handle; the column slides, except for those who
      turn animations off in their system.
    - **The header, in one line:** the lockup, the page's name after it,
      and a tagline; Help, Source and the light/dark switch on the
      right. The page is **puregrain lab**, the library stays puregrain
      (the user's choice: a place to try settings and compare results;
      "studio" would promise a full editor; and a photo lab is where
      grain is developed). The tagline puts the library and privacy at
      the top: "The puregrain library, at work in your browser: your
      pictures are never uploaded."; on phones, shorter: "Runs in your
      browser: nothing is uploaded." No second logo box: the logo stays
      modest.
    - **The empty picture area** holds the description (how to start)
      and the privacy promises: nothing uploaded, no ads, no
      registration, no tracking, free.
    - **One bar under the picture:** the zoom on the left; the run's
      state in the middle (the hint before dithering, the progress with
      the time left and Cancel, "Cancelled", an error); the actions on
      the right. The notes on settings stay in the column, next to their
      settings.
    - **The gallery** (v3) gets a strip under the bar.
    - **The footer:** the versions of the page and of the library
      ("puregrain lab v2, built on puregrain 0.2.0": the page's written
      in `Text.purs`, the library's read from `spago.yaml` at build
      time), the licenses (the code MIT, the logo its own terms),
      GitHub. Since 2026-11-03 (the user's design): the versions on the
      left, the links on the right, divided by thin lines within the
      footer's padding, drawn as borders so screen readers don't read
      them; on phones, where the links wrap, plain gaps instead. "Built
      on", not just "·", since two names alike read as a stutter to
      anyone who doesn't know that one is the page and the other the
      library.
    - **Phones:** the same column, hidden at first and opened over the
      picture by a settings button. An Apply button at its bottom closes
      it and starts the run; closing it any other way applies too.
      Unlike decision 16's start at each change, on purpose: on a phone
      the column covers the picture.
30. **The flow and the states** (2026-10-30):

    | State | Picture area | Bar under the picture | Settings column |
    |---|---|---|---|
    | Empty | drop zone, description, privacy promises | hidden | disabled; on phones no settings button |
    | Loading a file | the drop zone says "Loading photo.jpg…" | hidden | disabled |
    | Not a picture | a message above the drop zone | hidden | disabled |
    | Loaded, all at "none" | the original | "The original is shown. Choose colors or a method to dither it."; zoom; Download disabled | enabled |
    | Running | the previous result, or the original (B) | progress, the time left (decision 23), Cancel; Download disabled | enabled: a change restarts the run |
    | Finished | the split: original left, result right, handle, labels | zoom; Download | enabled |
    | Cancelled | the original | "Cancelled; the original is shown." | enabled |
    | The run failed | the original | the error | enabled |

    - **A. Errors stay in place** until the next action, not as toasts,
      which can vanish before they're read; a toast at most for a brief
      confirmation, such as "Copied".
    - **B. No flicker:** a new run keeps the previous result until the
      new one is ready; the original shows for the first run and after
      Cancel, when no result matches the settings. The progress shows
      only for a run of over 1 s: below that, no feedback is needed
      (Jakob Nielsen's limits, as for decision 23). Changes decision
      16's last sentence.
    - **C. A file that isn't a picture** leaves the loaded picture and
      its settings as they were, and the bar says so ("notes.txt isn't a
      picture; the current one stays"); until v2 the picture gave way to
      the error. Also right for several originals one day (the user).
    - **D. A drop anywhere on the page** loads the picture, so the
      browser never opens the file in place of the page. What's shown,
      as soon as a file is dragged over the page: in the empty state the
      drop zone lights up; with a picture, an overlay "Drop to load the
      picture" covers the picture area (the user's targets).
    - **E. Phones:** the settings button appears once a picture is
      loaded, left of the light/dark switch: a sliders icon, "Settings"
      for screen readers; not ☰, which means navigation.
31. **The components** (2026-10-30 and 31):
    - **The settings, as numbered steps:** 1 Picture, 2 Target, 3
      Colors, 4 Method, and 5 Background when the background shows.
    - **Picture:** its name and size, and "Choose another…", which keeps
      the settings and dithers the new picture at once, as before.
    - **Target:** three cards, each with a line on what it means ("any
      size, the colors you choose"; "256 × 192, 2 colors per 8×8 cell";
      "320 × 200, 2 colors per 8×8 cell").
    - **Colors:** a menu, the palettes grouped; with a machine, its
      palettes. The levels with − and + around their number; the
      threshold with a slider and a number, the slider starting a run
      when released, not at each step of a drag.
    - **Error diffusion:** a menu.
    - **Bayer map:** five segments, None, 2×2, 4×4, 8×8, 16×16; when it
      can't apply, disabled, with the note beside it saying why.
    - **Gray first:** a toggle switch, a native checkbox marked as a
      switch for screen readers: by the usual convention a switch takes
      effect at once, as every change on the page does (decision 16).
    - **The machine's hint** has "Use 8×8": one click, and still the
      user's choice (decision 16).
    - **Plain controls,** each with its label, and its notes beside it:
      the column and the phone's panel have the room. The user's idea of
      compact controls that grow when focused was dropped (the user): a
      native menu already shows its choices when opened, accessibly,
      while growing controls would need pop-ups of our own.
    - **Zoom:** four segments, 1× to 4×; 1× is the reset. A menu once
      there are more values (v3's magnifying, perhaps); the keys + and −
      (decision 33).
    - **The split handle** (decision 15): moved only by dragging it; a
      click on the picture doesn't move it, since on a touch screen
      dragging the picture scrolls it, and v3's pan needs that drag too.
      While it has focus, ← and → move it a column, with Shift ten, Home
      and End to the edges, like any slider, without scrolling the page.
      The knob stays in the visible part when the picture is taller than
      its area. "Original" and "Result" above the picture's corners, in
      the margin around it.
    - **Download** (decision 24's format menu, the user's idea): a
      button naming its format ("Download PNG"), with ▾ beside it when
      there are more: a machine's files, each with the name it's saved
      under, one that isn't possible disabled, with the reason. The
      button takes the format last chosen, falling back to PNG when that
      one isn't possible, its label always naming the format; the choice
      is kept, not the fallback, for the visit (keeping it for the next
      visit: later, if ever). With any screen, PNG only: no ▾.
    - **The command line** (Claude's idea): the settings as the CLI's
      command, with Copy, in the column. Postponed (2026-10-31, the
      user): it comes with the npm package, once `npx puregrain …` runs
      without the repository; until then the line couldn't be run as
      shown (see "Later ideas").
    - **Split or side by side, and "Start over":** v3 (see "Versions").
32. **The look** (2026-10-30 and 31):
    - **The themes,** as in Claude's design: dark with the ZX set of the
      logo and its green as the accent, light with the C64 set and its
      blue (the logo's own advice, from the colors' contrast). The logo
      stays modest; if it looks too big on the built page, its size
      changes then.
    - **The switch between them:** two states, light and dark, set from
      the system's setting at each load; the user's choice isn't kept, so
      the next load starts from the system's again. A third state,
      "Auto", would need explaining, and few would choose it.
    - **The rest as in Claude's mockup:** neutral grays, and the accent
      only on what's chosen or can be done (the selected card or
      segment, the main button, the focus ring, the step numbers); the
      picture's area darker than the column in the dark theme, a warm
      light gray in the light one. The system's own font for reading, a
      monospace font for numbers, sizes and file names; no web font, and
      no pixel font for the headings: the logo is pixel enough. Retro in
      a few details: the logo, the square step numbers, the drop zone's
      frame and the progress bar's leading edge in 2-pixel dithered
      dots, nearly square corners (3 px).
    - **"lab"** after the lockup in plain text, in the page's font and a
      muted color, so the logo stays as it is.
33. **Accessibility** (2026-10-31):
    - **Structure,** as in Claude's mockup: each step a group with its
      heading; every control labelled; the cards and segments are radio
      buttons, the switch a checkbox marked as a switch; the pictures
      have text alternatives ("The original", "The result: 4 levels,
      Atkinson").
    - **The keyboard:** Tab goes in reading order (header, column,
      picture, bar, footer). Two skip links appear on the first Tab,
      "Skip to the settings" and "Skip to the picture" (WCAG's bypass
      blocks), in place of a key for the controls. The phone's panel
      takes the focus when it opens and gives it back to the settings
      button when it closes; Escape closes it, and the download menu.
    - **Shortcuts** (the user's idea): a single character only where its
      control has focus, since otherwise it gets in the way of screen
      readers and typing (WCAG 2.1.4); modifiers for the global ones.

      | Action | Key |
      |---|---|
      | Choose a picture | Ctrl+O (Cmd+O on a Mac) |
      | Download, in the button's format | Ctrl+S (Cmd+S) |
      | Cancel the run | Esc, when no menu or panel is open |
      | Zoom in, out | + and −, while the picture area has focus |
      | Move the split | ← → (with Shift ten), Home, End, on the handle |

      Ctrl+O and Ctrl+S are taken over from the browser, as web editors
      do (checked in Firefox; Chrome and Safari on the manual
      checklist). No key to hide the column, and none for a step: Ctrl+2
      for Target was considered, but Ctrl or Cmd with a digit switches
      the browser's tabs.
    - **Contrast and focus:** text at least 4.5:1; the outlines of
      controls at least 3:1 against their background (WCAG AA; Claude's
      mockup had 1.4:1; about `#5d6677` in the dark theme, `#92958f` in
      the light); the 2-pixel focus ring in the accent, never removed.
    - **Screen readers** hear the run's milestones (start, done, Cancel,
      errors), not each step of the progress; errors at once.
    - **No motion** (the column's slide, the switch's) for those who turn
      animations off; everything clicked or tapped at least 24 × 24
      pixels (WCAG 2.2), the handle's knob 32, 40 on phones.
34. **The technical choices** (2026-10-31; the facts, with their sources
    and checks, in `CLAUDE.md`, "Facts for v2's design"):
    - **Our own stylesheet instead of Pico** (decision 8): the mockup's
      design styles are 3.1 KB gzipped, Pico 11.6 KB, and its defaults
      would be overridden nearly everywhere. Pico leaves the
      dependencies and the build.
    - **CSS:** custom properties for the themes, media queries for the
      layout, `:has()` for the cards, `color-mix()`: all in the current
      Chrome, Edge, Firefox and Safari.
    - **The phone's panel is the column itself,** the rest of the page
      `inert` while it's open (checked), not `<dialog>`: one element
      serves both layouts. Our code handles Escape and the focus;
      opening it adds a step to the browser's history, so the back
      gesture closes it instead of leaving the page.
    - **The download menu:** a button that shows a list of buttons (the
      disclosure pattern), not the ARIA menu pattern, which promises
      arrow keys and type-ahead. Placed in its box, as in the mockup, not
      with anchor positioning (`position-anchor` in full only since
      Chrome 151, Firefox 151, Safari 27); Escape and a click outside
      close it.
    - **The split handle:** pointer events with capture (mouse, pen,
      touch); touch dragging taken over only on the handle, so the
      picture still scrolls by touch; the knob `position: sticky`
      (checked); the slider's keys.
    - **The drag overlay:** counting the drag events that enter and leave
      elements (they fire for each child), shown only while files are
      dragged; the counting a pure function with a spec.
    - **The theme:** the system's setting read at each load, a theme
      attribute on the page, `color-scheme` so the browser's own controls
      follow; the logo as the 1× PNGs with sharp pixels (2.9 and 4.6 KB,
      against 33 KB SVGs), CSS showing the theme's set, copied from
      `logo/` by the build, like the icons.
    - **Icons:** small inline SVGs (sliders, sun and moon, chevrons, the
      knob's arrows), not characters such as ☾ ☼ ◐, which render
      differently from system to system, as emoji on some.
    - **Copy,** for the command line, once it comes (decision 31): the
      browser's clipboard, which needs HTTPS or localhost: Pages and the
      dev server are.
    - **Halogen stays** (the user asked): its cost is paid once, about 19
      KB gzipped of the page's 34; the heavy work runs in the worker, and
      the page's updates are small; it keeps one language with the
      library, typed state, and the rules as pure functions tested in
      Node, and makes the page the library's second client. In phase 6,
      `App.purs` gets its rendering split into modules (header, column,
      picture area, bar), one component unless a part needs its own
      state.

## v1 in detail

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
  box, so they share zoom and scrolling. The original shows left of the
  split, the result right of it; the split moves by whole picture
  columns, starts in the middle for each picture and stays there across
  runs (phase 4).
- **Download:** the result as a PNG, named after the picture and the
  settings, with the CLI's names in the form's order:
  `photo-levels4-atkinson-bayer8.png` (Claude's addition, phase 4: a
  name per setting tells several downloads apart).
- **Tests:** as in decision 14.

## Phase 0 results of v1 (2026-10-20)

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

## Phase 0 results of v2 (2026-10-22)

Everything v2's phase 1 needs is in the library and the CLI already; the
package facts are in `web/CLAUDE.md`.

### The machine path in the worker

- **No library change.** The CLI dithers a machine's screen in memory
  (`ditherCells`); `ditherBands` gives the same bands lazily (the
  library pins the two equal), with all its work inside `defer`: a
  band's rows are read and dithered only when the band is forced. So the
  worker can report progress between bands with today's API.
- **Rows read as needed:** the input is a lazy list made with `unfoldr`,
  whose step runs only when its cell is forced; a pure function reads a
  row from the job's pixels, which nothing writes during the run. So a
  poster of any size holds about one band at a time: as RGB records, a
  6000 × 4000 picture would be 24 million objects.
- **The loop:** force the next band, write its rows into the result's
  pixels, keep its cells, report the rows done, counted from the band
  (decision 21). At the end, for a picture of the screen's size, the
  file writers get `{ cells, image }`, the image read back from the
  result's pixels (a screen is only 49,152 or 64,000 pixels).
- **Gray and color:** as in the CLI, "gray first" turns the picture gray
  before anything else, and a machine's screen always runs on RGB.
- **Checked against the CLI** as in v1's phase 3: a spec compares the
  worker's band loop with the CLI's path (`ditherCells` on the whole
  picture) for each machine and rule; the browser check compares the
  downloaded files with the CLI's, byte for byte.

### The CLI's rules to mirror

- **Names:** `zx-spectrum`, with the palettes `full` (the default),
  `normal` and `bright` (`Zx.screen`, `Zx.normalScreen`,
  `Zx.brightScreen`); `c64-hires`, with only `full`
  (`C64.hiresScreen`).
- **Inside the cells:** `nearestInCell`, or `orderedInCell (bayer n)`
  with a Bayer map; any kernel. So the page offers a Bayer map with a
  machine too.
- **The size:** a PNG of any size, with a note naming the screen's size
  and the picture's; the files only at 256 × 192 or 320 × 200.
- **The tape's name:** the CLI's `tapeName`, on the picture's name (the
  name without its extension, codes 32 to 126 only, the first 10). The
  library takes an empty name too (10 spaces on the tape); `puregrain`
  instead is the page's choice (decision 21).
- **Defaults:** the CLI's kernel is Floyd–Steinberg (none with
  `--bayer`); the page keeps none and shows the hint (decisions 16, 21).
- **Download names:** the colors' part is the machine's name, with its
  palette unless it's the full one: `photo-zx-spectrum-bright-bayer8.tap`,
  `photo-c64-hires-atkinson.prg`.

### Downloads made from bytes

- The writers give `Either String (Array Int)`. `web-file` makes a
  `Blob` only from strings, so a few lines of FFI make one from bytes,
  saved like the PNG (a link with `download`, its URL revoked later), as
  `application/octet-stream`.
- The worker makes the files, since it has the cells, and sends them with
  the result's pixels, transferred: `.scr` 6912 bytes, `.tap` 6980,
  `.prg` 14,145, `.art` 9009. The job carries the tape's name.

### The estimate's rule (decision 23)

- **The clock** is the page's: `Effect.Now.now` (package `now`, in our
  set; `web-html` has no `performance`), in milliseconds, from posting
  the job to each progress message.
- **A pure function, with a spec:** the time left, elapsed ÷ done ×
  (total − done), and whether to show it (a predicted total over 10 s;
  once shown, the page keeps showing it). Its text lives in `Text.purs`.
  Proposed rounding, to settle in phase 3: under a minute in steps of 5
  s ("about 45 s left"), up to 10 minutes as minutes and steps of 10 s
  ("about 2 min 30 s left"), beyond that in whole minutes.

## Open questions

None left for v2: the last, the logo in the root README, was settled in
phase 7 (decision 28).

## Later ideas

- The page's settings as the CLI's command, with Copy (decision 31),
  once the CLI is on npm and `npx puregrain …` runs without the
  repository (TODO.md, "npm package").
- The background's default from the page's theme, in dark mode
  (decision 27 has white).
- Translations of the UI's texts.
- Keeping transparency in the output, for icons and sprites: in TODO.md's
  future directions, since it concerns the library and the CLI too.

## Phases of v1

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

## Progress of v1

- [x] 0. Verify and design
- [x] 1. Setup: the package, the two bundles, the dev server; checked in headless Firefox
- [x] 2. Load and show: picker, drop, decoding, whole-number zoom; checked in headless Firefox at ratios 1 and 1.5
- [x] 3. Settings and dithering: the form, the worker with the stepper, progress, cancelling; the results equal the CLI's
- [x] 4. Compare and save: the split view with a range input, the PNG download; checked in headless Firefox at ratios 1 and 1.5
- [x] 5. Delivery: user docs in `README.md`, with the manual checklist (decision 14)

## Phases of v2

The scope and the phases are settled now; the technical details and the
design before each phase; and the plan is corrected as the phases teach
us (the user's proposal, 2026-10-22). The sizes are rough.

0. **Verify and design, no code** (small): the machine path in the
   worker (`Puregrain.Cells.ditherBands` with the rows read as needed,
   progress after each band, the `{ cells, image }` record the file
   writers take); the CLI's rules to mirror (the size check, the tape's
   name, how the defaults combine); downloads made from bytes; the
   estimate's rule.
1. **Machine screens** (large): decision 21. The settings, the worker's
   band path, the four files, the downloads; the results checked against
   the CLI's, by specs and in the browser.
2. **Preparing the picture** (medium): fitting it to the machine's
   screen (decision 22), and the background color for transparent parts
   (decision 27).
3. **The time estimate** (small): decision 23.
4. **The logo** (medium): its concept and colors, the script that makes
   it with puregrain, SVG and PNG, the favicon (decision 28, `logo/`);
   before the page's design (decision 24).
5. **Design review** (medium, mostly discussion): the screen's areas in
   text, sketches, components, the technical choices (decision 24).
   Done: decisions 29 to 34.
6. **Design** (large): decisions 29 to 34, in six steps. Each ends with
   the specs and `npm run check` green, its checks in headless Firefox,
   screenshots for the user, and the user's commit.
   1. **Foundations:** our own stylesheet in place of Pico; the two
      themes (the system's setting at load, the toggle switch, the
      logo's PNGs copied from `logo/`); the skeleton: header, column,
      picture area, bar, footer with the versions; `App.purs`'s
      rendering split into modules. Everything the page does today works
      in its new place; phones get a simple stacked layout until step 5.
   2. **The settings column:** the numbered steps, the Target cards, the
      colors' menu with the levels' stepper and the threshold's slider,
      the Bayer segments, the toggle switch, the background's swatch,
      the notes beside their settings, "Use 8×8", the « / » tab, and
      the column disabled on the empty page.
   3. **The picture area and the bar:** the drop zone with the
      description and the promises, "Loading…", a bad file keeping the
      picture, the drag overlay; the split handle (pointer, keys, the
      sticky knob, labels); the previous result kept during a run, the
      progress after 1 s; the bar's messages, the zoom's segments.
   4. **Download and keys:** the button naming its format, with its list
      of formats; the remembered format and its fallback; Ctrl/Cmd+S and
      +O, Esc, + and −.
   5. **Phones:** the column as a panel, opened by the settings button,
      closed with Apply; the rest `inert`, the focus in and out, Escape,
      the back gesture; the run when the panel closes; the short
      tagline.
   6. **Accessibility and docs:** skip links, the announcements, text
      alternatives, reduced motion, 3:1 outlines, target sizes; a scan
      with axe-core, run from Claude's scratchpad, not a dependency;
      `README.md` (using it, the checklist), `CLAUDE.md`, this file.

   The checks: specs for each new rule (the download's format and its
   fallback, when the progress shows, which picture shows during a run,
   the bar's message in each state, the drag counter, the panel holding
   changes until it closes, a bad file keeping the picture); in headless
   Firefox, the results still the CLI's, the split exact to the screen
   pixel, the downloads byte for byte, the keyboard paths, both themes,
   both widths, reduced motion; the manual checklist for what only
   Chrome and Safari can show (Ctrl+S and +O there, phones).
7. **Delivery of v2** (medium): user docs, the checklist and the
   CLAUDE.md notes; the smoke test (decision 25); the Pages workflow
   (decision 26); the pull request, with the logo in the root README and
   CONTRIBUTING.md's branching rule (decisions 1 and 13); Pages switched
   on (the user's, just before the merge); after the merge, the
   checklist on the live page, on phones and in Safari and Chrome, with
   fixes on `master`.

## Progress of v2

- [x] 0. Verify and design: the machine path needs no library change; the CLI's rules, downloads from bytes, the estimate's clock
- [x] 1. Machine screens: the target menu, both machines with their palettes, the band loop with progress, the four files; the screens and files equal the CLI's, byte for byte
- [x] 2. Preparing the picture: the background under transparent parts, read exactly through WebGL, and the fit by our own area averaging; both equal independent references, and the dithered results the CLI's
- [x] 3. The time estimate: shown for runs predicted over 10 s, rounded in steps, kept to the end; within 20% of the time actually left in Firefox
- [x] 4. The logo: the mark, the wordmark, the lockup and the swash in two color sets, dithered by puregrain; SVG, PNG, the favicons and the social preview; its own terms; the SVGs and the icons checked in Firefox
- [x] 5. Design review: two designs made separately, compared goal by goal; decisions 29 to 34, and phase 6's plan
- [x] 6. Design: decisions 29 to 34 built in six steps, each checked in headless Firefox: our own stylesheet in place of Pico, the two themes, the page's skeleton; the settings' column as numbered steps, with the « / » tab; the picture area and the bar (the drop zone, the drag's overlay, a bad file keeping the picture, the split's handle with its sticky knob, the result kept during a run, the progress after a second); download and keys (the button naming its format with ▾ and its list, the format kept with its fallback, Ctrl/Cmd+O and +S, Esc, + and −); phones (the settings as a panel over the screen, with Apply, the runs held until it closes, the back gesture); accessibility (skip links, live regions for the run's milestones and errors, the pictures' names, an `<h1>`, contrast and target sizes measured, axe-core 4.14.0 finding nothing)
- [ ] 7. Delivery
