# Similar tools: a survey

An internal working document: what else converts pictures with
dithering, and where puregrain stands among them, the facts behind its
positioning. Part 1, the converters for
retro machines, was made on 2026-11-03; part 2, general dithering tools
and libraries, is still to come.

The facts come from each tool's own README or page, and one overview
article; nothing here was tested by us. "Not stated" means the sources
don't say, not that the feature is missing. Links: [Sources](#sources).

## Part 1: converters for retro machines

| Tool | Runs as | Machines | Native files | Dithering | Colors | License; tests (as stated) |
|---|---|---|---|---|---|---|
| [Dithertron](https://github.com/sehugg/dithertron) (Steven Hugg, 8bitworkshop) | browser; library on npm (`@8bws/dithertron`, TypeScript) | about 90 targets: C64 hires, multicolor and FLI; ZX Spectrum (5 variants); Amstrad CPC 0 and 1; MSX through the TMS9918A; NES, Game Boy, Apple II, Atari, Amiga, SNES and more | a packed binary (`.bin`) and a viewer project in 8bitworkshop; no machine file types | diffusion by amount, Bayer blended in; a cell's colors chosen by simulated annealing, iterated until neighbouring cells settle | 4 error functions: perceptual, hue, distance, maximum | GPL-3.0, its exports CC0; unit and headless-browser tests; "check pixel-exact source images" is on its TODO list |
| [Retro Pixel Converter](https://github.com/factus10/retro-pixel-converter) (David Anderson) | browser, from a local `index.html`; needs WebGL2 | 8: ZX81, ZX Spectrum, Timex 2068 (also its 8×1 and 64-column modes), C64 hires and multicolor, Atari 800, Sinclair QL, SAM Coupé, PICO-8; custom modes from JSON | `.scr`, `.tap`, `.prg`, Koala `.kla`, Atari `.mic` `.gr8` `.gr9`, QL, SAM `.ss1`–`.ss4`, ZX81 `.zx8` | 16: Floyd–Steinberg, Atkinson, Stucki, JJN, Burkes, Sierra Lite, Riemersma variants, blue noise, Bayer 4 and 8, halftone, and more | dithers in linear light; several ways to choose a cell's colors, one of them "segment coverage" | GPL-3; tests not mentioned |
| [RetroPixels+](https://meatloaf.cc/tools/retropixels+/) (Jaime Idolpx, on Michel de Bree's [retropixels](https://github.com/micheldebree/retropixels)) | browser; retropixels also as a CLI (its repository archived) | C64 only: Koala multicolor, Art Studio hires, FLI, AFLI, NUFLI (incomplete) | `.prg`, PNG; PAL or NTSC | error diffusion, Bayer, none | several palettes and color spaces | not stated |
| [ZX Spectrumizer](https://atornblad.github.io/zx-spectrumizer/) (Anders Marzi Tornblad) | browser | ZX Spectrum only | `.tap`; plays the loading sound | an unnamed dither option; a black-and-white mode | an optional saturation boost | open source, license not stated |
| [ZX PixelPaste](https://www.mb-maniax.cz/zxpp/) (MB Maniax) | browser; an editor more than a converter | ZX Spectrum 48 and 128, ZX Spectrum Next | `.scr`, attributes, `.bin`, `.asm` | Bayer, Floyd–Steinberg | the Next's 256 colors | not stated |
| [BitPast](https://portwally.github.io/Bitpast/) | macOS app (App Store) | 15 machines, among them ZX Spectrum, C64 (also PETSCII), Amstrad CPC, MSX, BBC Micro, Apple II, Atari, Amiga, IBM PC | over 20 formats (`.scr`, `.prg`, Koala, Art Studio, `.sc2`…) and disk images (`.trd`, `.d64`, `.dsk`…) | "15+ algorithms", not named | not stated | not stated |
| [RetroPIC](https://github.com/marlow75/retropic) | Java desktop app | C64, C16/Plus/4, VIC-20, C128, ZX Spectrum, Amstrad CPC, Atari ST, Amiga, PC CGA/VESA text | `.prg`, Koala, Art Studio, `.scr`, DEGAS, IFF, `.com` | Bayer, blue noise, Floyd–Steinberg, noise, Atkinson | not stated | not stated |
| [Img2Spec](https://github.com/jarikomppa/img2spec) (Jari Komppa) | desktop app | ZX Spectrum | its own `.isw`, a C header | not described; "an artist tool", with manual adjustment | not stated | not stated |
| **puregrain** | library (PureScript), CLI, browser | ZX Spectrum (all colors, normal, bright), C64 hires | `.scr`, a self-loading `.tap`, a `.prg` with a BASIC viewer, Art Studio `.art` | 11 kernels since 0.2.1 (Floyd–Steinberg, Atkinson, JJN, Stucki, Burkes, three Sierras, Fan, two by Shiau and Fan; the web app 4 of them until its v2.2) and your own; Bayer 2 to 16 and your own maps, also inside cells | nearest color in RGB; linear light and perceptual distance planned | MIT; property tests against an independent reference, 20 CLI checks over 68 runs, 57 browser checks; the same bytes from the library, the CLI and the web app |

## What it says about puregrain

- **Behind: breadth.** Two machine modes against 8 (Retro Pixel Converter),
  15 (BitPast) or about 90 (Dithertron). A race for machines can't be won
  against Dithertron.
- **Behind: methods and color.** Retro Pixel Converter has 16 dithering
  methods and dithers in linear light; Dithertron has perceptual error
  functions. The eight kernels of 0.2.1 (2026-11-05) narrow that gap, and
  the planned linear light and perceptual distance would close it; none
  of it sets puregrain apart.
- **Level: native files.** Several tools write `.scr`, `.tap`, `.prg` or
  Koala; BitPast writes even disk images. A self-loading tape and a viewer
  program are good, but not unique (ZX Spectrumizer writes a `.tap` too).
- **Alone, as far as these sources show:**
  1. **Exactness:** the same result from a library, a CLI and a web app,
     proved by tests against an independent reference. No other tool
     claims it; Dithertron lists pixel-exactness as a TODO.
  2. **A permissive library:** the only other library, Dithertron's, is
     GPL-3.0, so a program that uses it must be GPL too. puregrain is MIT.
  3. **Evidence for the recommendations:** the count of 300 real loading
     screens behind 2×2 and 4×4 (see
     [machine-screens/README.md](machine-screens/README.md#which-mode-for-which-picture)).
     None of the tools publishes such a method.
  4. **Streaming and a stepper:** pictures of any size, row by row, from
     any source. For screens of 256 × 192 that matters little; for a
     library it does.
- **Not compared:** privacy and accessibility. Dithertron and Retro Pixel
  Converter run in the browser too, so pictures stay local there as well;
  none of the sources mentions accessibility.

So "authentic 8-bit screens" alone is a claim many tools can make;
"exactly", and an MIT library to build on, are puregrain's own.

## Part 2: general dithering tools and libraries (to come)

Seen so far (2026-11-03, from their pages' scripts):

- [ditherit.com](https://ditherit.com/): Nuxt (Vue), its own code in a web
  worker; 13 kernels, blue noise, Riemersma; linear light, OKLab for
  color distance; Fathom analytics.
- [fumagalli.ar](https://fumagalli.ar/articles/mdx/introduction-to-dithering):
  an article with demos, Next.js (React); error diffusion in a web
  worker, Bayer and Thomas Knoll's pattern dithering in WebGL 2 shaders.

To survey: ImageMagick, libdither, didder, image-q, and web apps such as
Dither Me This.

## Sources

- Dithertron: [README](https://github.com/sehugg/dithertron), [the app](https://8bitworkshop.com/dithertron/)
- Retro Pixel Converter: [README](https://github.com/factus10/retro-pixel-converter), [the app](https://factus10.github.io/retro-pixel-converter/)
- The overview by Retro Pixel Converter's author: [A constellation of retro pixel converters](https://timexsinclair.com/blog/a-constellation-of-retro-pixel-converters/)
- RetroPixels+: [the app](https://meatloaf.cc/tools/retropixels+/), [an article on it (2026-01-27)](https://theoasisbbs.com/browser-c64-image-converter-retropixels-in-your-tab/), [retropixels](https://github.com/micheldebree/retropixels)
- ZX Spectrumizer: [the app and its notes](https://atornblad.github.io/zx-spectrumizer/)
- ZX PixelPaste: [the app](https://www.mb-maniax.cz/zxpp/)
- BitPast: [its page](https://portwally.github.io/Bitpast/)
- RetroPIC: [README](https://github.com/marlow75/retropic)
- Img2Spec: [README](https://github.com/jarikomppa/img2spec)
