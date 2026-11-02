# puregrain-web

Dithering in the browser, built on the puregrain library in this
repository: choose a picture, choose how to dither it, for any screen or
for a ZX Spectrum's or a Commodore 64's, and compare the result with the
original, pixel for pixel, before saving it as a PNG or as the machine's
own files. The same settings give the same pixels and files as the
[command-line tool](../cli/README.md), for pictures without transparency
(see below).

> **Status: version 2,** the first on GitHub Pages: designed, checked
> for accessibility, and checked in three browser engines. Version 3 is
> planned ([ROADMAP.md](ROADMAP.md)).

## Running it

Online, with nothing to install:
[roman-mkh.github.io/puregrain](https://roman-mkh.github.io/puregrain/).

From a checkout of this repository, at its root (needs Node.js):

```bash
npm install         # once: the PureScript toolchain and esbuild
npm run web:build   # compiles and bundles the page into web/dist/
npm run web:serve   # serves web/dist/ on http://localhost:8000
```

Then open http://localhost:8000. Ctrl+C stops the server. The page needs
a server, even locally: browsers don't start the page's worker, which does
the dithering, for a page opened as a file. After changing a source, run
`npm run web:build` again and reload the page.

## Using it

The settings are on the left, in numbered steps, and the picture on the
right, with a bar under it: the zoom, how the dithering is going, and
the download. The « tab on the settings' edge hides them, so the picture
gets the whole width, and » brings them back. On a phone the picture
fills the page, and the settings open over it (see below).

1. **Choose a picture** (step 1, Picture): with "Choose a picture…", or
   by dropping it anywhere on the page; the empty page's drop zone lights
   up while a file is dragged over it, and with a picture shown, "Drop to
   load the picture" covers it. Any picture the browser can read works:
   PNG, JPEG, GIF, WebP, BMP and more. A file that isn't a picture leaves
   the one shown as it was, and the bar under the picture says so. The
   colors are read as the file stores them, without its color profile,
   as the command-line tool reads them. Transparent parts go onto a
   background color, white unless you choose another in step 5,
   Background, which appears for such a picture.
2. **Choose the settings.** They start at "none", and the page shows the
   original. As in the command-line tool, they choose:
   - **the target** (step 2): any screen, or a machine's: the ZX
     Spectrum's, or the Commodore 64's hires screen, where each 8×8 cell
     may use only two colors
     ([machine screens](../docs/machine-screens/README.md));
   - **the colors** (step 3), which follow the target: for any screen,
     gray, black and white at a threshold (0–255, with a slider and a
     number), a number of levels per channel (2–256, with − and +), or
     one of the palettes; for the Spectrum all its 15 colors, the normal
     ones only or the bright ones only; for the C64 its 16;
   - **the method** (step 4): error diffusion (Floyd–Steinberg, Atkinson
     or Jarvis–Judice–Ninke), ordered dithering with a Bayer map (2×2 to
     16×16), or both. A Bayer map works over levels, or inside a
     machine's cells, so it isn't offered with a threshold or a palette,
     and a note beside it says why. For black and white with a Bayer map,
     choose 2 levels and "Turn the picture gray first" (the command-line
     tool's `--bayer 8 --gray`): 2 levels per channel would give a color
     picture 8 colors.

   "Turn the picture gray first" does that before dithering. Choosing a
   machine dithers its screen at once, with all its colors. Choosing a
   method while the colors are still "none" chooses them too: a threshold
   at 128 for a kernel, 2 levels for a Bayer map, or a machine's colors.
   With a machine and no method, each pixel just takes the nearer of its
   cell's colors, and the page recommends ordered dithering, 8×8, with a
   button that chooses it.
3. **Dithering starts by itself** with each change, in the background, so
   the page keeps responding. A run that takes more than a second shows a
   progress bar, × to cancel it, and the rows done: "Dithering: 465/1536
   rows"; a change during a run starts it over. A run that looks like it
   will take over 10 seconds shows the time left first, from the pace so
   far: "Dithering: about 45 s left (465/1536 rows)", "about 2 min 30 s
   left", "a few seconds left". Meanwhile the result before it stays on show;
   the original shows until a picture's first result is there, again
   after a new target, fit or background, and after Cancel.
4. **Compare.** The original shows left of the split and the result right
   of it, as the labels above the picture's corners say. Drag the split's
   handle, or give it the focus (Tab) and move it with ← and → (ten
   columns with Shift), Home and End. The zoom, 1× to 4×, makes each
   picture pixel exactly 1 to 4 screen pixels wide, whatever the screen's
   density, so the dither pattern stays sharp: at any other scale it
   would blur or form moiré. A large picture scrolls in its area.
5. **Download.** As a PNG, or for a machine's screen also as the
   machine's own files: the Spectrum's screen file (`.scr`) and a tape
   that loads it (`.tap`), or a C64 program that shows the picture
   (`.prg`) and an Art Studio picture (`.art`)
   ([what they are, and how to open them](../docs/machine-screens/README.md)).
   The button under the picture names its format, "Download PNG"; for a
   machine, ▾ beside it lists the formats, each with the name it's saved
   under. Choosing one saves it, and the button takes that format from
   then on, falling back to PNG while it isn't possible (with another
   target, say) and coming back to it after.
   The files need a picture of the screen's size, 256×192 or 320×200. For
   any other size the page says so, offers the PNG, a poster in the
   machine's style, and offers to **fit the picture to the screen**:
   scaled down, never up, so that it covers the screen as far as it can,
   centered, cropped where it overflows, and the background color where
   it doesn't reach. A 6000×4000 photo becomes 288×192 and loses 16
   columns on each side; a 100×80 icon stays as it is, centered on the
   background. The page says what it did, and the fitted picture is what
   the split view shows as the original. A file is named after the
   picture and the settings: `photo.jpg` with 4 levels, Atkinson and the
   8×8 Bayer map becomes `photo-levels4-atkinson-bayer8.png`, and fitted
   to the Spectrum's screen with the 8×8 map
   `photo-zx-spectrum-fit-bayer8.tap`; a background that shows and isn't
   white adds `bg-` and its color, as in `logo-bg-2a5ac8-levels4.png`.
   The name on the tape is the picture's name, as the command-line tool
   makes it from its output's: without the extension, printable ASCII
   only, at most 10 characters (`puregrain` when nothing is left).

**On a phone,** the settings open from the sliders button in the
header, once a picture is loaded, over the whole screen. Changes made
there wait: Apply closes the settings and dithers with them, and so do
the back gesture and Esc.

**Where the focus goes:** the empty page starts with it on "Choose a
picture…", so Enter opens the file chooser (Shift+Tab goes back to the
header and the skip links). Once the first picture is there, it moves on
to the next step, the target; a later picture leaves it on "Choose
another…".

**Keys:** Ctrl+O chooses a picture and Ctrl+S downloads in the button's
format (Cmd works as Ctrl, on a Mac and elsewhere); Esc closes the
phone's settings or the list of formats, or cancels a run. While the
picture area has the focus (Tab, or a click on it), + and − zoom; while
the split's handle has it, ← and → move it a column (ten with Shift),
Home and End to the edges. The tooltips show the keys.

**Light or dark:** the page follows the system's setting each time it
loads; the switch in the header changes it until the next load.

**With the keyboard alone, or a screen reader:** the first Tab shows two
skip links, to the settings and to the picture. Every control is
labelled, each step is a group with its heading, and the pictures have
names ("The result: 4 levels, Atkinson"). Screen readers hear when a long
run starts, when a result is done ("Done: 4 levels, Atkinson."), a
cancelled run, and errors at once, but not each step of the progress.
Nothing moves (the settings' slide, the switches) for those who turn
animations off in their system. The standard it follows:
[Accessibility](#accessibility).

What each kernel, Bayer map and palette does, and how gray and color are
chosen, is in the command-line tool's documentation:
[kernels](../cli/README.md#kernels),
[ordered dithering](../cli/README.md#ordered-dithering),
[palettes](../cli/README.md#palettes),
[how the output is chosen](../cli/README.md#how-the-output-is-chosen).

## The same settings in the command-line tool

| On the page | `npm run dither-cli -- IN.png OUT.png ...` |
|---|---|
| Target: a machine | `--machine NAME` (`zx-spectrum`, `c64-hires`) |
| Colors, for a machine | `--machine-palette NAME` (`full`, `normal`, `bright`) |
| Colors: gray, black and white at a threshold | `--threshold T` |
| Colors: levels per channel | `--levels N` |
| Colors: a palette | `--palette NAME` (`bw`, `websafe216`, `cga16`, `ansi16`, `ansi256`, `c64`, `zx15`) |
| Error diffusion | `--kernel NAME` (`none`, `floyd-steinberg`, `atkinson`, `jjn`) |
| Ordered dithering (Bayer map) | `--bayer N` |
| Turn the picture gray first | `--gray` |

A downloaded file's name spells these options:
`photo-levels4-atkinson-bayer8.png` is
`--levels 4 --kernel atkinson --bayer 8`. One difference: a setting the
page leaves at "none" isn't in the name, but the command-line tool's
kernel defaults to Floyd–Steinberg (to none with `--bayer`). For
`photo-threshold128.png`, the command line therefore needs
`--threshold 128 --kernel none`.

The pixels are the same, and so are a machine's files, byte for byte.
A PNG's bytes aren't: the browser writes its own PNGs (Firefox: 8-bit
RGBA), while the command-line tool writes gray results as grayscale PNGs
and color ones as RGB.

**Not yet for a picture with transparent parts, or a fitted one:** the
page puts transparent parts onto the background color, while the
command-line tool ignores transparency and dithers the colors the file
stores under them; and the command-line tool can't fit a picture yet.
Both are planned for it, with the page's rules (`--background`,
`--fit`). Until then, a fitted picture saved as a PNG and given to the
command-line tool gives the same result.

## Privacy

Everything happens in your browser: the picture isn't sent anywhere, and
the page loads nothing from other sites. All its files come from its own
build.

## Browsers

Made for the current desktop versions of Chrome, Edge, Firefox and
Safari; phones on a best-effort basis. Its results, its downloads and
its split are checked automatically in those browsers' engines, as
Playwright builds them for Linux (Chromium, Firefox and WebKit; see
[Development](#development)); everything else so far only in Firefox.

## Accessibility

The page aims at level AA of the W3C's
[Web Content Accessibility Guidelines (WCAG) 2.2](https://www.w3.org/TR/WCAG22/),
which includes level A. Among other things, that means:

- everything works with the keyboard alone, the focus always in sight,
  with skip links to the settings and to the picture;
- text has a contrast of at least 4.5:1 against its background, and the
  outlines of controls at least 3:1;
- whatever can be clicked or tapped is at least 24 × 24 pixels, or
  spaced as WCAG 2.2 allows;
- screen readers get a name for every control and picture, and hear the
  run's milestones and errors;
- nothing moves for those who turn animations off.

How far that's checked: in Firefox, by axe-core's WCAG 2.2 A and AA
rules, which find nothing, and by measuring the contrast, the target
sizes, the focus at every Tab stop and the keyboard paths. Not yet with a
screen reader, nor in Chrome and Safari: those are on the
[checklist](#checking-a-change-by-hand). Automatic checks find only part
of what WCAG asks, so this is the aim, not a claim of conformance. Level
AAA isn't aimed at.

## Limitations

- A picture is never enlarged: a small one stays small on the machine's
  screen, with the background around it.
- In a browser without WebGL, the colors at a picture's semi-transparent
  edges may be off by one after the background is put under them.
- One result at a time. Keeping several and comparing them comes later.
- No size limit: a large picture takes a while (a 1024×1024 color
  picture a few seconds, in Firefox on the development machine). The
  progress bar and the time left show how far it is.
- The library's limitations apply too: no linear-light diffusion, plain
  RGB distance for palettes, rows always scanned left to right (see
  [the command-line tool's limitations](../cli/README.md#limitations)).

## Development

- The web UI is the `puregrain-web` package of the spago workspace
  (`web/spago.yaml`), in [Halogen](https://github.com/purescript-halogen/purescript-halogen).
  Its sources are in `web/src/Puregrain/Web/`:
  - `App.purs` is the page, a Halogen component: what it shows and how
    it reacts; the decisions are in the pure modules. `Text.purs` holds
    every text it shows.
  - `Settings.purs` (the choices and their rules), `Dither.purs` (the
    settings as library values, as the command-line tool builds them),
    `Save.purs` (the files' names and the tape's), `Status.purs` (what
    the picture area and the bar show for a run), `Split.purs` (the split
    handle's drag and keys), `Drag.purs` (a drag of files over the page),
    `Download.purs` (the download's formats), `Keys.purs` (the
    shortcuts) and `Zoom.purs` are pure, and tested.
  - `Worker.purs` is the worker's entry; `Run.purs` dithers row by row
    with the library's stepper, or a machine's screen band by band, a row
    of cells at a time, reports progress, and makes the machine's files;
    `Message.purs` holds the messages between the page and the worker.
  - `Page`, `Picture`, `Pixels`, `Pointer`, `Prepare`, `Save` and
    `Screen` reach the browser through a few lines of JavaScript each.
- `web/build.mjs` (`npm run web:build`) bundles the page and the worker
  with spago and esbuild into `web/dist/` (not committed), and copies
  `web/static/` (the page and its stylesheet) and the logo's icons,
  lockups and marks (from `logo/`) there.
- `npm test` runs the package's specs with the other suites: the
  settings' rules, the worker's dithering and a machine's files against
  the command-line tool's path, the messages, the names, the zoom, what
  the bar says, the split handle's keys, the drag's count, the download's
  formats and the shortcuts.
- `npm run check:web` (`scripts/check-web.mjs`) checks the page itself in
  Chromium, Firefox and WebKit, the engines of Chrome and Edge, Firefox
  and Safari: for four settings, one for each kind of colors, the
  downloaded PNG has the command-line tool's pixels; for both machines,
  the PNG too, and their files are the tool's, byte for byte; the split
  is exact to the screen pixel. It needs Docker, usable without sudo: the
  browsers run in Playwright's image, which the first run downloads
  (about 1 GB). Build first (`npm run build`, `npm run web:build`);
  `npm run check` builds both and runs it last.
- The plan, the decisions and their reasons: [ROADMAP.md](ROADMAP.md).
  Architecture and gotchas: [CLAUDE.md](CLAUDE.md), notes kept for the
  AI assistant used in development.

### Checking a change by hand

What the specs can't reach, the browser itself, is checked by hand.
`npm run check:web` takes the exact parts in three engines: the results
and the downloads against the command-line tool's (items 7 to 9), and
the split, exact to the screen pixel (item 6); the rest, and Chrome, Edge
and Safari themselves, stay here. After `npm run web:build` and a reload,
ideally in each of the browsers above:

1. A PNG chosen with the file chooser and a JPEG dropped onto the page
   both show. While a file is dragged over the page, the empty page's
   drop zone lights up, or "Drop to load the picture" covers a picture.
   A file that isn't a picture gives a message, and a picture shown
   stays.
2. A picture with transparent parts shows them white.
3. Each zoom keeps the pixels sharp; a large picture scrolls.
4. The settings start at "none", showing the original. A kernel brings a
   threshold at 128, a Bayer map 2 levels; the Bayer map is unavailable
   with a threshold or a palette.
5. A large picture (a photo of a few megapixels) shows the progress after
   a second, rising, the page keeps responding, and Cancel brings back
   the original. A change during a run starts a new one, the result
   before it staying until the new one is there.
6. The split shows the original on the left and the result on the right,
   and stays where it is when a setting changes. Its handle follows the
   mouse, and a finger on a touch screen, where the picture still
   scrolls when touched elsewhere; with the focus, the arrow keys, Home
   and End move it. On a picture taller than its area, the handle's knob
   stays in sight while it scrolls.
7. The downloaded file has the settings in its name and shows the result.
   For a machine, ▾ lists the formats; one chosen there becomes the
   button's, and PNG takes its place while it isn't possible.
8. A result looks like the command-line tool's with the same settings
   (the table above), both viewed at 100%.
9. A machine as the target: its colors only, its screen dithered at
   once, with the hint until a method is chosen. At the screen's size
   (`npm run generate-images` makes `samples/color-256x192.png` and
   `samples/color-320x200.png`), the machine's files are in the list of
   formats and open in an emulator; at any other size, the note, and
   only the PNG possible.
10. Fitting to the screen: a large picture is scaled down and cropped, a
   small one centered on the background, each with a note saying so; the
   fit stays on for the next picture, and unticking it brings the poster
   back. A picture with transparency (a PNG icon) shows the background's
   color picker, and a new color changes what's under the transparent
   parts.
11. A run of more than 10 seconds (a picture of 10 megapixels or more)
   shows the time left after a few seconds, counting down in steps, and
   keeps it to the end; a short run shows none.
12. Ctrl+O opens the file chooser and Ctrl+S downloads (Cmd on a Mac),
   without the browser's own dialogs, in Chrome and Safari too (checked
   in Firefox by the development checks); Esc cancels a run.
13. On a phone (Chrome on Android, Safari on an iPhone): the sliders
   button opens the settings over the whole screen, sliding in; changes
   start nothing until Apply, which closes them and dithers; the back
   gesture does the same and stays on the page.
14. With the keyboard alone: the empty page starts on "Choose a
   picture…", and the first picture moves the focus to the target; the
   skip links, before them, take the focus to the settings and to the
   picture; every control is reached in reading order (header, settings,
   picture, bar, footer), with its focus ring in sight; the list of
   formats opens and closes (Esc) without the mouse.
15. With a screen reader (NVDA with Firefox or Chrome, VoiceOver with
   Safari): the steps are read as groups with their headings, the
   pictures by their names; "Done: …" follows a run, "Dithering…" a long
   one's first second, and an error is read at once; the phone's
   settings are a dialog.
16. At 200% of the browser's own zoom, the page still fits, nothing is
   cut off or overlaps, and the picture stays sharp; both themes read
   well, and the switch changes between them.
17. The browser's tab shows the puregrain icon, "Pg" in red and green.
18. The browser's console shows no errors.
