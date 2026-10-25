# puregrain-web

Dithering in the browser, built on the puregrain library in this
repository: choose a picture, choose how to dither it, for any screen or
for a ZX Spectrum's or a Commodore 64's, and compare the result with the
original, pixel for pixel, before saving it as a PNG or as the machine's
own files. The same settings give the same pixels and files as the
[command-line tool](../cli/README.md), for pictures without transparency
(see below).

> **Status: version 2 in progress, functional but not styled yet,** on
> the `web-ui` branch. It isn't hosted anywhere yet, so run it from a
> checkout of this repository. The design and more come with the rest of
> version 2 ([ROADMAP.md](ROADMAP.md)).

## Running it

From the repository root (needs Node.js):

```bash
npm install         # once: the PureScript toolchain, esbuild, Pico CSS
npm run web:build   # compiles and bundles the page into web/dist/
npm run web:serve   # serves web/dist/ on http://localhost:8000
```

Then open http://localhost:8000. Ctrl+C stops the server. The page needs
a server, even locally: browsers don't start the page's worker, which does
the dithering, for a page opened as a file. After changing a source, run
`npm run web:build` again and reload the page.

## Using it

1. **Choose a picture,** with the file chooser or by dropping it onto the
   page. Any picture the browser can read works: PNG, JPEG, GIF, WebP,
   BMP and more. The colors are read as the file stores them, without its
   color profile, as the command-line tool reads them. Transparent parts
   go onto a background color, white unless you choose another: the page
   offers a color picker for a picture with transparency.
2. **Choose the settings.** They start at "none", and the page shows the
   original. As in the command-line tool, they choose:
   - **the target:** any screen, or a machine's: the ZX Spectrum's, or the
     Commodore 64's hires screen, where each 8×8 cell may use only two
     colors ([machine screens](../docs/machine-screens/README.md));
   - **the colors**, which follow the target: for any screen, gray, black
     and white at a threshold (0–255), a number of levels per channel
     (2–256), or one of the palettes; for the Spectrum all its 15 colors,
     the normal ones only or the bright ones only; for the C64 its 16;
   - **the method:** error diffusion (Floyd–Steinberg, Atkinson or
     Jarvis–Judice–Ninke), ordered dithering with a Bayer map (2×2 to
     16×16), or both. A Bayer map works over levels, or inside a
     machine's cells, so it isn't offered with a threshold or a palette.
     For black and white with a Bayer map, choose 2 levels and "Turn the
     picture gray first" (the command-line tool's `--bayer 8 --gray`):
     2 levels per channel would give a color picture 8 colors.

   "Turn the picture gray first" does that before dithering. Choosing a
   machine dithers its screen at once, with all its colors. Choosing a
   method while the colors are still "none" chooses them too: a threshold
   at 128 for a kernel, 2 levels for a Bayer map, or a machine's colors.
   With a machine and no method, each pixel just takes the nearer of its
   cell's colors, and the page recommends ordered dithering, 8×8.
3. **Dithering starts by itself** with each change, in the background, so
   the page keeps responding. A progress bar shows the rows done, and
   Cancel stops it; a change during a run starts it over. Until the
   result is there, the original is shown.
4. **Compare.** The original shows left of the split and the result right
   of it; the slider moves the split. The zoom, 1× to 4×, makes each
   picture pixel exactly 1 to 4 screen pixels wide, whatever the screen's
   density, so the dither pattern stays sharp: at any other scale it
   would blur or form moiré. A large picture scrolls in its box.
5. **Download.** As a PNG, or for a machine's screen also as the
   machine's own files: the Spectrum's screen file (`.scr`) and a tape
   that loads it (`.tap`), or a C64 program that shows the picture
   (`.prg`) and an Art Studio picture (`.art`)
   ([what they are, and how to open them](../docs/machine-screens/README.md)).
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
Safari; phones on a best-effort basis. So far it's been checked in
Firefox.

## Limitations

- A picture is never enlarged: a small one stays small on the machine's
  screen, with the background around it.
- In a browser without WebGL, the colors at a picture's semi-transparent
  edges may be off by one after the background is put under them.
- One result at a time. Keeping several and comparing them comes later.
- No size limit, and no estimate of the time yet: a large picture takes
  a while (a 1024×1024 color picture a few seconds, in Firefox on the
  development machine). The progress bar shows how far it is.
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
    `Save.purs` (the files' names and the tape's) and `Zoom.purs` are
    pure, and tested.
  - `Worker.purs` is the worker's entry; `Run.purs` dithers row by row
    with the library's stepper, or a machine's screen band by band, a row
    of cells at a time, reports progress, and makes the machine's files;
    `Message.purs` holds the messages between the page and the worker.
  - `Picture`, `Pixels`, `Save` and `Screen` reach the browser through a
    few lines of JavaScript each.
- `web/build.mjs` (`npm run web:build`) bundles the page and the worker
  with spago and esbuild into `web/dist/` (not committed), and copies
  `web/static/` and Pico CSS there.
- `npm test` runs the package's specs with the other suites: the
  settings' rules, the worker's dithering and a machine's files against
  the command-line tool's path, the messages, the names and the zoom.
- The plan, the decisions and their reasons: [ROADMAP.md](ROADMAP.md).
  Architecture and gotchas: [CLAUDE.md](CLAUDE.md), notes kept for the
  AI assistant used in development.

### Checking a change by hand

What the specs can't reach, the browser itself, is checked by hand. After
`npm run web:build` and a reload, ideally in each of the browsers above:

1. A PNG chosen with the file chooser and a JPEG dropped onto the page
   both show; a file that isn't a picture gives a message.
2. A picture with transparent parts shows them white.
3. Each zoom keeps the pixels sharp; a large picture scrolls.
4. The settings start at "none", showing the original. A kernel brings a
   threshold at 128, a Bayer map 2 levels; the Bayer map is unavailable
   with a threshold or a palette.
5. A large picture (a photo of a few megapixels) shows the progress rising,
   the page keeps responding, and Cancel brings back the original. A
   change during a run starts a new one.
6. The split shows the original on the left and the result on the right,
   and stays where it is when a setting changes.
7. The downloaded file has the settings in its name and shows the result.
8. A result looks like the command-line tool's with the same settings
   (the table above), both viewed at 100%.
9. A machine as the target: its colors only, its screen dithered at
   once, with the hint until a method is chosen. At the screen's size
   (`npm run generate-images` makes `samples/color-256x192.png` and
   `samples/color-320x200.png`), the machine's files come with buttons
   and open in an emulator; at any other size, the note, and the PNG only.
10. Fitting to the screen: a large picture is scaled down and cropped, a
   small one centered on the background, each with a note saying so; the
   fit stays on for the next picture, and unticking it brings the poster
   back. A picture with transparency (a PNG icon) shows the background's
   color picker, and a new color changes what's under the transparent
   parts.
11. The browser's console shows no errors.
