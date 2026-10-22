# Logo: ideas

Working notes for the project's logo, made in the web UI's v2
([ROADMAP.md](ROADMAP.md), phase 4). Only the approach is agreed so far;
the questions below are open.

## Where it's used

- The web UI: the page's header and its favicon.
- The root `README.md`'s header, from the merge into `master` on, and so
  Pursuit too, which shows the README.
- GitHub's social preview image (1280 × 640, set in the repository's
  settings), if wanted.
- Later the npm package's page.

## The approach: puregrain draws its own logo

A script draws a small source picture, dithers it with the CLI, and
writes the result as an SVG with one rectangle per run of dots: crisp at
any size, small, reproducible, and it shows what the library does. The
results are committed, with a script to make them again, like the
test-image previews (`npm run docs:images`).

## Ideas for the mark

1. **A dithered sphere,** the classic subject of dithering demos; it
   stays readable even as a favicon.
2. **A grain** of wheat or rice, shaded and dithered: a play on the name.
3. **A monogram,** a "p" filled with a dithered gradient.
4. One of these with the word "puregrain", for the README's header.

## Questions to settle

- Black and white, one accent color, or a retro palette (the C64's, the
  ZX Spectrum's)?
- Floyd–Steinberg's organic grain, or Bayer's retro crosshatch?
- How big the dots are: a source of about 32 to 48 pixels keeps them
  visible.
- Dithered in linear light or not, once the library offers it (TODO.md).
- The license: MIT with the code is simplest; some projects keep their
  logo under its own terms.

## Technical points

- **Dark mode:** black dots vanish on GitHub's dark theme. Either two
  variants, chosen by `<picture>` with `prefers-color-scheme`, or a color
  that works on light and dark backgrounds.
- **Pursuit** shows the README, and an image with a relative path
  probably breaks there, so the README may need an absolute URL. To
  check.
- **Favicon:** current Chrome, Edge and Firefox take an SVG; check
  Safari, and add a PNG (and an `apple-touch-icon`) where needed.
- **Pinned settings:** the script names every setting it dithers with, so
  that a change of the CLI's defaults doesn't change the logo by accident
  (linear light is planned to become the default).

## When

In its own phase of v2 (phase 4 in ROADMAP.md), before the page's design,
whose direction it may set; on `web-ui`, since the page needs it. The
README gets it with the merge into `master` at the end of v2.
