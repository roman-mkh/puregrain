# puregrain-web

Dithering in the browser, built on the puregrain library in this
repository: choose a picture, choose how to dither it, and compare the
result with the original, pixel for pixel, before saving it as a PNG. The
same settings give the same pixels as the
[command-line tool](../cli/README.md).

> **Status: version 1, functional but not styled yet,** on the `web-ui`
> branch. It isn't hosted anywhere yet, so run it from a checkout of this
> repository. Machine screens, the design and more come in later versions
> ([ROADMAP.md](ROADMAP.md)).

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
   color profile, as the command-line tool reads them; transparent parts
   become white.
2. **Choose the settings.** They start at "none", and the page shows the
   original. As in the command-line tool, they choose two things:
   - **the colors:** gray, black and white at a threshold (0–255), a
     number of levels per channel (2–256), or one of the palettes;
   - **the method:** error diffusion (Floyd–Steinberg, Atkinson or
     Jarvis–Judice–Ninke), ordered dithering with a Bayer map (2×2 to
     16×16), or both. A Bayer map works over levels, so it isn't offered
     with a threshold or a palette.

   "Turn the picture gray first" does that before dithering. Choosing a
   method while the colors are still "none" chooses them too: a threshold
   at 128 for a kernel, 2 levels for a Bayer map.
3. **Dithering starts by itself** with each change, in the background, so
   the page keeps responding. A progress bar shows the rows done, and
   Cancel stops it; a change during a run starts it over. Until the
   result is there, the original is shown.
4. **Compare.** The original shows left of the split and the result right
   of it; the slider moves the split. The zoom, 1× to 4×, makes each
   picture pixel exactly 1 to 4 screen pixels wide, whatever the screen's
   density, so the dither pattern stays sharp: at any other scale it
   would blur or form moiré. A large picture scrolls in its box.
5. **Download as PNG.** The file is named after the picture and the
   settings: `photo.jpg` with 4 levels, Atkinson and the 8×8 Bayer map
   becomes `photo-levels4-atkinson-bayer8.png`.

What each kernel, Bayer map and palette does, and how gray and color are
chosen, is in the command-line tool's documentation:
[kernels](../cli/README.md#kernels),
[ordered dithering](../cli/README.md#ordered-dithering),
[palettes](../cli/README.md#palettes),
[how the output is chosen](../cli/README.md#how-the-output-is-chosen).

## The same settings in the command-line tool

| On the page | `npm run dither-cli -- IN.png OUT.png ...` |
|---|---|
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

The pixels are the same, not the files' bytes: the browser writes its own
PNGs (Firefox: 8-bit RGBA), while the command-line tool writes gray
results as grayscale PNGs and color ones as RGB.

## Privacy

Everything happens in your browser: the picture isn't sent anywhere, and
the page loads nothing from other sites. All its files come from its own
build.

## Browsers

Made for the current desktop versions of Chrome, Edge, Firefox and
Safari; phones on a best-effort basis. So far it's been checked in
Firefox.

## Limitations

- Only PNG output, and no machine screens yet: the command-line tool's
  `--machine zx-spectrum` and `--machine c64-hires`, with their files,
  come in version 2.
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
    `Save.purs` (the file name) and `Zoom.purs` are pure, and tested.
  - `Worker.purs` is the worker's entry; `Run.purs` dithers row by row
    with the library's stepper and reports progress; `Message.purs` holds
    the messages between the page and the worker.
  - `Picture`, `Pixels`, `Save` and `Screen` reach the browser through a
    few lines of JavaScript each.
- `web/build.mjs` (`npm run web:build`) bundles the page and the worker
  with spago and esbuild into `web/dist/` (not committed), and copies
  `web/static/` and Pico CSS there.
- `npm test` runs the package's specs with the other suites: the
  settings' rules, the worker's dithering against the command-line tool's
  path, the messages, the file names and the zoom.
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
9. The browser's console shows no errors.
