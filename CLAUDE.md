# puregrain — project memory

A PureScript library for dithering (Floyd–Steinberg, Atkinson, JJN, ...),
targeting eventual publication on Pursuit + an npm wrapper. This file
captures architectural decisions and rationale from the design
conversation that built this codebase, since a lot of it isn't visible
from the code alone.

@docs/benchmarks-dithering.md
@TODO.md

## Workspace layout (spago monorepo)

- **`puregrain`** (root `spago.yaml`, `src/`, `test/`) — the library.
  Its dependencies are what every Pursuit user inherits, so they must
  stay exact: keep `spago build --pedantic-packages` clean, keep
  test-only packages under `test.dependencies`, and never add
  Node-only or app packages here. MIT-licensed (`LICENSE` at the root
  covers the library and the CLI; the logo in `logo/` has terms of its
  own, see below); `package.publish` in `spago.yaml`
  holds the license and the current version (0.3.0), and
  `package.json` says `"license": "MIT"` too.
- **`puregrain-cli`** (`cli/spago.yaml`, `cli/src/`, modules
  `Puregrain.Cli.*`) — the command-line tool, a separate package that
  depends on the library. The only JS in it is the pngjs wrapper
  (`Puregrain.Cli.Png`) and the clock (`Puregrain.Cli.Timing`): `timed f x`
  reads `performance.now` around `f x` inside JS, on purpose. Timed in
  PureScript (clock, `let result = f unit`, clock), purs-backend-es
  inlined it and moved the pure dithering after the second clock read
  (0.0 ms, 2026-10-10); code inside a foreign function can't be moved, and
  `x` is evaluated before the call, so the gray conversion stays outside
  the measurement in every build. Run through `npm run dither-cli -- ...`:
  the launcher `cli/bin/puregrain-cli.mjs` runs the compiled output
  directly, with no rebuild per run (benchmark timings rely on this).
  `PUREGRAIN_OUTPUT=output-es` makes it run the purs-backend-es build
  (`npm run build:es`) instead of `output/`.
  `npm run check:cli` runs its end-to-end exact checks. User docs:
  `cli/README.md` (quick start, options, modes, examples). Keep
  `Puregrain.Cli.Main` I/O-only: decisions go in `Puregrain.Cli.Pipeline`
  (pure, tested in `cli/test/`). Kernel/palette CLI names are defined
  once (`kernelName`/`paletteName`); tables and help text derive from
  them, and `check-cli.sh` reads the kernels' names from the compiled
  `allKernels`/`kernelName`, so its checks 2 and 6 run every kernel, a
  new one included (2026-11-05; check 2 on the palette tile at 128×128,
  the same patches in a sixteenth of the time: every kernel at 512×512
  would have added 68 s). `--kernel none` is the empty kernel. `--bayer N` (2–16) is its own
  option; how it combines with the quantizer options (only with
  `--levels`; `--palette` is rejected) is checked after optparse, in
  `Options.resolve`, whose rejections `parseOptions` turns into ordinary
  optparse failures (same usage text, exit code 1) — optparse's
  alternatives commit to the first matching option, so the rule can't be
  an alternative without defining `--levels` twice. Without `--kernel`,
  `--bayer` means no diffusion, pure ordered dithering, and every other
  mode Floyd–Steinberg (decided 2026-10-14): the kernel option has no
  optparse default, `resolve` fills it in. It's the one per-mode default,
  because with `--bayer` the kernel decides the method (pure or the
  hybrid), not just the texture; a global default of none was rejected,
  since every other mode would then stop dithering by default. Floyd–
  Steinberg stays the general default: it passes on all the error (true
  tones), with few neighbours (of the kernels that do, only Sierra Lite,
  since 0.2.1, has fewer: 3 to its 4), and it's the classic. `--machine NAME`
  (2026-10-11; names from `machineName`, now `zx-spectrum` and, since
  2026-10-17, `c64-hires`; constructors `ZxSpectrumScreen` and
  `C64HiresScreen`, since `ZxSpectrum` and `C64` are the palettes'; that palette's
  CLI name was renamed from `zx-spectrum` to `zx15` on 2026-10-11, named by
  its color count like `cga16`, so `zx-spectrum` means only the real
  look; the CLI isn't published, so nobody outside broke) is a quantizer
  choice of its own, `Machine { name, bayer }`: `resolve` rejects it with
  `--threshold`, `--levels`, `--palette` (the machine defines the colors);
  `--bayer N` is allowed since 2026-10-15, ordered dithering inside the
  cells (pure by the `--bayer` kernel default, the hybrid with
  `--kernel`); `--kernel` and `--gray` work. `Pipeline` routes it to a
  third pipeline, `Screen m rule` (RGB), the rule being `nearestInCell`
  or `orderedInCell` with the Bayer map; the PipelineSpec compares rules
  by dithering a 16 × 12 probe without diffusion, as it compares
  quantizers by probes. `ditherScreen` calls `ditherCells` with the
  machine's mode and returns a `DitheredScreen`, one constructor per
  machine (`ZxDithered`, `C64HiresDithered`), since each holds its own
  machine's cells, which its files need; `screenImage` reads the picture.
  The output
  format, `png`, `scr`, `tap`, `prg` or `art` (names from `formatName`), comes from the
  output file's extension, in any case (since 2026-10-16; the user's
  suggestion), or from `--format NAME`, which always wins: `--format png`
  writes a PNG under any name, on purpose. An extension that names no
  format, without `--format`, is rejected with advice (`out.jpg` used to
  get PNG bytes silently; a typo like `out.pgn` is now caught). Only the
  format is inferred, never the machine: `.scr` is the Amstrad CPC's
  screen extension too. `splitFileName` (in `Options`) splits the name,
  for the format and for the tape name alike. Only the chosen file is
  written (decided 2026-10-12: one option for the format, no second file
  next to the PNG). `resolve` rejects `scr` and `tap` output without
  `--machine zx-spectrum`, and `prg` and `art` without `--machine c64-hires`,
  matching the machine without a wildcard, so a
  new machine must decide its formats. `--machine-palette NAME`
  (2026-10-17, the user's design) picks which of the machine's colors
  the cells may use: `full` (the default), `normal` and `bright`, the
  Spectrum's own terms (preferred wherever there are some; `no-bright`
  was rejected for `normal`). It needs `--machine`; `machinePalettesOf`
  lists each machine's palettes, the default first (no wildcard, so a new
  machine must list its own): `c64-hires` offers only `full`, and
  `resolve` rejects the others, naming the machine's. Kept narrow on purpose: it chooses a
  set of colors and nothing else. A machine's screen modes with other
  cell sizes, or variants of its color values, would be another option
  or machine name, and `--machine-*` options must not multiply without
  control (the user's caution). Reusing `--palette` was rejected: it
  means per-pixel colors without cells. `screenSizeCheck`
  runs before dithering: for an image other than the machine's screen
  (256×192, or 320×200 for `c64-hires`), a note with a
  PNG (any size works, e.g. a poster), an error with `scr`, `tap`, `prg` or `art` (exit
  1, no file). `screenFile` maps a dithered screen to its encoder (`Zx.toScr`),
  `tapeFile` to its tape writer (`Zx.toTap`, 2026-10-16, `--format tap`),
  with the name from `tapeName`: the output file's name without directory
  and extension, printable ASCII only, cut to 10. For a C64 screen both
  are `Left` (the options never ask for them). `programFile`
  (2026-10-17, `--format prg`) maps a C64 hires screen to
  `C64.toHiresPrg`, a `.prg` with a BASIC viewer (its layout and viewer:
  `docs/machine-screens/c64.md`), and
  `artStudioFile` (2026-10-18, `--format art`) to `C64.toArtStudio`, an
  Art Studio picture; for a ZX screen both are `Left`. `Main` writes the bytes
  with `node-fs`/`node-buffer`, no JS of our own.
  `--gamma NAME` (2026-11-14; "Linear light" under Key design decisions):
  `off` (the default; `1.0` and `1` are accepted too, the help shows
  "off (the default, also 1.0)"), `1.2`, `1.5`, `1.8` or `srgb`
  (`gammaChoice`); it combines with every mode. `Main` always calls the
  library's `…With` drivers (`gammaOf`), and the report line names the
  gamma only when it isn't `off`, so with `off` it reads as before.
  `--gray` and the gray pipeline use the library's `toGray` (`toNeutral`
  takes the gamma; the CLI's own `luma` is gone). `--check-engine` is a
  mode of its own, like `--help`: optparse has two alternatives, so
  `parseOptions` returns `Command = CheckEngine | Dither Options`, and the
  usage line shows both; it prints "Engine check passed: …" and exits 0,
  or "Engine check failed:" with the problems on standard error and exits
  1. `check:cli`'s checks 13 to 16 cover the gamma (70 s instead of 39).
  `--version` (2026-11-17, the user's request) prints `puregrain X.Y.Z`
  with the library's version: the CLI isn't released on its own, so the
  two are coupled (the user: the lab numbers its versions on its own, the
  CLI follows the library). A constant, `version` in `Options`, since a
  bundled CLI on npm won't have `spago.yaml` to read; `OptionsSpec` reads
  the root `spago.yaml` and fails while the two differ, so the release
  commit sets both (CONTRIBUTING.md, step 1), and `check:cli`'s check 17
  runs it through the launcher. optparse's `infoOption`: exit 0, like
  `--help`. The CLI calls itself `puregrain` (2026-11-18, for the npm
  package, see `npm/` below): the
  name users type, `programName` in `Options`, in the help's header, the
  usage line and `--version`; the workspace package stays `puregrain-cli`.
  `Main.answered` is optparse's `handleParseResult` with that name fixed:
  optparse's own takes the script's file name (split at "/" only), which
  an npm link or Windows' wrapper would make `cli.mjs`. It sets the exit
  code and returns instead of exiting at once, so a long help is written
  out in full through a pipe; completion keeps optparse's handling.
  `exitcodes` and `enums` became the CLI's own dependencies for it.
  Check 17 also runs `--help` and a rejected command line through the
  launcher (mutation-checked: optparse's handler shows `puregrain-cli.mjs`).
  `spago test` runs both packages' suites (library, then CLI).
- **`npm/`** (2026-11-17/18, branch `npm-package`) — the npm package
  `puregrain`: the command-line tool, bundled; the JavaScript API later
  joins the same package (TODO.md). The spec, with every measurement:
  `git show 872b3f3:docs/npm-package-spec.md`. `npm/package.json` is the
  manifest without a version (the build adds the library's, so an
  `npm publish` in `npm/` itself fails); `npm/README.md` the npm page,
  its links to `master` moved to the release's tag by the build (the
  logo's included: a later change can't alter a published version's
  page); `npm/build.mjs` (`npm run npm:build`) writes `npm/dist/`
  (gitignored), the folder published: `cli.mjs`, `package.json`,
  `README.md`, `LICENSE` (npm takes nothing from a parent folder),
  `THIRD-PARTY-NOTICES.txt`. The bundle is `spago bundle`'s, like the
  lab's, with **one `--bundler-args` per esbuild option**
  (`--external:pngjs`, `--minify-whitespace`, `--minify-syntax`): spago
  hands each value to esbuild as one argument, so options joined in one
  value were silently ignored (pngjs bundled, nothing minified); the
  build checks spago's `#!/usr/bin/env node` line and that pngjs is
  imported, not bundled (mutation-checked). Decided with the user:
  - the package and the command `puregrain`, for good (renaming the
    command would break scripts); the CLI calls itself so (above);
  - the version the library's; the first npm version was the next
    release's, 0.3.0, published with its tag (not 0.2.2: its tag lacks the
    CLI's changes since, and the shared version must identify the
    release); from then on the CLI's options are a public contract;
  - pngjs a dependency, `~7.0.0`, not bundled: patch fixes reach users,
    `npm audit` sees it, the bundle stays small;
  - `"exports"` allows only `./package.json`, so the API's entry later
    only adds (`bin` doesn't depend on it);
  - minified except for names: 406 → 273 KB (60 KB packed), names kept
    for readable stack traces; bundling took the startup from 199 ms
    (the launcher's ~190 files) to 60 ms, minifying added nothing; tree
    shaking is esbuild's anyway; not purs-backend-es (the checks test
    the purs build); the engine check passes in the bundle;
  - Node 22 or later; `"author": "roman-mkh (https://github.com/roman-mkh)"`.

  **Third-party notices** (`scripts/third-party-notices.mjs`, for the npm
  bundle and the lab's scripts): a bundle is a binary form, and most of
  the bundled packages' BSD-style licenses ask for their notices with it.
  It follows the compiled modules' imports from the entry modules (a
  superset of what esbuild keeps, by design), maps modules to packages by
  their sources in `.spago/p/<name>-<version>/` (versions from
  `spago.lock`), and writes plain text (a `.md` might be downloaded by a
  browser), each license in full. It fails on an npm import not allowed
  for the bundle (`pngjs` for the CLI). `exitcodes` (the CLI's, through
  optparse) and `freeap` (the lab's, through Halogen) have no license
  text anywhere, only "MIT" in their manifests: the notices say so.
  `npm run check:npm` (`scripts/check-npm.mjs`, after `npm:build`):
  packs `npm/dist/`, installs the tarball into an empty temporary folder
  (pngjs from the registry: it needs the network), runs the command
  through npm's link, compares seven configurations with the launcher
  byte for byte (a `.tap` carries its file's name, so both outputs are
  named alike), checks that imports are refused, and compares the
  notices with what esbuild bundles, for both bundles; a package without
  a license text beyond the two known fails it. Publishing:
  CONTRIBUTING.md, release step 6, by the user (`npm login`, two-factor
  authentication); the npm account's email is public in every package's
  metadata (`npm view <package> maintainers` shows it).
- **`puregrain-examples`** (`examples/spago.yaml`, `examples/src/`,
  modules `Puregrain.Examples.*`, added 2026-10-08) — small programs for
  users, no tests: `QuickStart` (a gray gradient made in code, and the
  same gradient dithered with Floyd–Steinberg, printed as text art) and
  `Compare` (no diffusion, Floyd–Steinberg, Bayer). They import only the
  `Puregrain` facade and print text, so they need no image files and no
  JS. Run with `npx spago run -p puregrain-examples -m <module>`, or play
  in `npx spago repl -p puregrain-examples` (`examples/README.md`). The
  build compiles them, so an API change that breaks them fails CI. Text
  art: `shades` in `QuickStart` (one editable list, █ = white for dark
  terminals; reverse it for light backgrounds), 2 characters per pixel
  for square pixels, every line within 80 columns. `examples/try/
  TryQuickStart.purs` (2026-11-16) is QuickStart for Try PureScript,
  which has puregrain in its package list (`staging/spago.yaml` in
  purescript/trypurescript, a package set's packages); the README links
  it with `?github=roman-mkh/puregrain/master/examples/try/
  TryQuickStart.purs`. Module `Main` (what Try PureScript runs), output
  through Try PureScript's own `TryPureScript` (`render =<< withConsole`,
  imported qualified, since it has a `render` of its own), the shades
  reversed for its light page, a comment inviting other kernels. Outside
  `examples/src/`, so spago never compiles it (`TryPureScript` exists
  only there), and CI doesn't check it: keep it in step with QuickStart
  by hand. Checked by the user on try.purescript.org, 2026-11-16. No
  badge for it: PureScript projects use none, and the style guide asks
  for a clear link to an example.
- **`puregrain-web`** (`web/spago.yaml`, `web/src/`, modules
  `Puregrain.Web.*`; developed from 2026-10-20 on the long-lived branch
  `web-ui`, merged into `master` at the end of v2)
  — the web UI, the library's second real client, in Halogen. Its
  name for users is **puregrain lab** (decided 2026-11-17): the user docs
  say "puregrain lab", or "the lab" after the first mention; the developer
  material (the code, `web/spago.yaml`, CLAUDE.md files, the roadmap,
  CONTRIBUTING.md) keeps "puregrain-web" and "the web UI". The lab has
  its own version numbers (v2.4), apart from the library's. Its plan,
  decisions and open questions are in `web/ROADMAP.md`; its architecture
  and gotchas in `web/CLAUDE.md`, which Claude Code reads when working
  in `web/`; its user docs, with a manual checklist, in `web/README.md`.
  `npm run web:build` bundles it into `web/dist/` (gitignored),
  `npm run web:serve` serves that on localhost:8000. The workspace's
  strict build compiles it, so a library change that breaks it fails
  `npm run check` and CI. Version 1 (functional, not styled) was done on
  2026-10-21: loading, the settings, dithering in a worker with progress
  and cancelling, the split view, the PNG download. `npm run check:web`
  (2026-11-01; decision 25 in `web/ROADMAP.md`, with its reasons) checks
  the page end to end in Chromium, Firefox and WebKit against the CLI's
  results and files: Playwright drives the browsers, which run in its
  Docker image, and only they do; the rest stays on the host (details
  and gotchas in `web/CLAUDE.md`).
- **`logo/`** (2026-10-26; decision 28 in `web/ROADMAP.md`)
  — the project's logo, made by puregrain: `make-logo.mjs` draws the
  shapes, dithers gray gradients through the CLI, and writes SVG and PNG
  per color set (`zx/` and `c64/`, equal, chosen by what fits around
  them; `logo/README.md` recommends the ZX set on dark backgrounds, from
  the colors' contrast), and the favicons and the social preview in the
  ZX set, since they must work on any background; the web build copies
  the three icons into the page. `npm run logo`, after `npm run build`. Every CLI setting is given
  (`--levels 2 --bayer N --kernel none --gray --gamma off`), so a change
  of the CLI's defaults can't change the logo (`--gamma off` since
  2026-11-14: off is the default, but `--gray` depends on the gamma); after
  a change to the CLI, `npm run logo` must report every file unchanged. It writes a file only
  when its pixels changed, since zlib may compress the same pixels to
  other bytes on another Node. **Not MIT:** the whole folder, the script
  included (it holds the design), is under `logo/LICENSE.md` (decided
  with the user 2026-10-26: unchanged, to refer to puregrain or show
  it's used, and in copies of the repository for working on it; not as
  the logo of a modified version or of anything else). The root
  `LICENSE` stays plain MIT, so GitHub keeps showing "MIT" (its license
  detection, Licensee, reads only the root and a top-level `LICENSES/`);
  the README's License section names the exception. User docs:
  `logo/README.md`.
- **`pictures/`** (2026-11-21) — the sample picture,
  `macaw-and-toucan.png`, to try puregrain on, from a checkout and in
  puregrain lab (v2.4, decision 35 in `web/ROADMAP.md`): "try the sample
  picture" before the first picture, in the drop zone and in step 1's
  hint; the web build copies the file into `web/dist/pictures/`, fetched
  only on a click; `check:web` loads it both ways, and blocked, and
  compares a run (`cga16`, Floyd–Steinberg, gamma 1.8) with the CLI's.
  AI-generated: Lumo (Proton) made a 1280 × 720 JPEG (16:9, it offers no
  16:10), cut to 1152 × 720 (16:10, 64 columns off each side) and
  stored losslessly as a PNG, since browsers may decode
  one JPEG to different pixels and a PNG decodes alike everywhere; the
  JPEG's compression stays in it. Chosen by the user over a second try
  with whole tails: bigger birds. MIT like the repository (Lumo's terms
  give the output to the user; the README says an AI picture may have no
  copyright at all). Its `README.md` has the prompt word for word and the
  examples, from a checkout and with `npx` after a `curl` of the file
  (not in the npm package, which stays small). Committed once: a
  replaced version would stay in git's history for good. Not in
  `samples/`, which is gitignored scratch.
- **`.purs-repl`** (the REPL's startup file, at the workspace root) is
  committed, through an exception in `.gitignore` (since 2026-10-08;
  spago's own template ignores `.purs*` and treats it as personal, and
  `spago repl` creates it with `import Prelude` when it's missing). It
  imports `Prelude`, `Effect.Console (log)` and `Puregrain as P`. Keep it
  to modules every package's REPL has: the library's REPL works too,
  because spago always adds `psci-support`, which brings `console` and
  `effect`. Never `Puregrain.Examples.*`: only the examples' REPL has
  them, and every other REPL would start with an error.
- Module names must be unique across all packages in the workspace
  (shared `output/`) — hence no `Main` modules; entry points get
  qualified names like `Puregrain.Cli.Main`.
- The future web GUI would be another sibling package. Splitting
  packages into separate repos is possible later; the package
  boundary is what matters.

## Documentation map

- `CONTRIBUTING.md` — the workflow rules (setup, branches, CI,
  versions, release checklist).
- `CHANGELOG.md` — the changes per version of the library and, under
  `### Command-line tool`, of the CLI, the npm package (decided
  2026-11-18: one file, since they share their versions); new entries go
  under `## Unreleased` (rules in `CONTRIBUTING.md`).
- `README.md` — lean entry point by decision: what it is, status,
  features (each linking to its doc), "When to use it, and when not",
  getting started, layout, doc index. "When to use it" (2026-10-08) is
  2 + 2 situations, not a repeat of the features: use it for dithering
  inside a PureScript program, and for large or streamed images; look
  elsewhere when speed matters or for the best photo quality. No timings
  there, only a link to the benchmarks: the numbers depend on the
  machine, and the benchmarks doc describes ours. Its "Getting started"
  (for PureScript developers) shows an
  excerpt of `examples/src/Puregrain/Examples/QuickStart.purs` (the
  import, `gradient`, `main`), copied by hand: **when `QuickStart.purs`
  changes, refresh the excerpt, and `examples/try/TryQuickStart.purs`**. A script checking the copy was
  considered and dropped (2026-10-08): more machinery than a 15-line
  excerpt needs. The program's printed output isn't shown (dropped
  2026-10-08): text art made for a dark terminal looks inverted on light
  pages (Pursuit, GitHub's default), and Pursuit's code font (Roboto
  Mono) probably lacks the block characters, so a fallback font could
  misalign them. The README says in words what the terminal shows.
  Its heading is the logo (2026-11-01): the ZX lockup, one picture for
  GitHub's light and dark pages and for Pursuit, which rewrites the
  relative path (decision 28 in `web/ROADMAP.md`).
- `examples/README.md` — the example programs: what each shows, how to
  run them, a REPL session with variations to try.
- Reference docs live in `docs/` and are the single source of truth:
  `error-diffusion.md` (2026-11-05: the 11 kernels, each with its table,
  other names, sources, and what it's good for as the sources say it;
  the project's own observations marked *seen here*; its tables were
  checked against the compiled presets by a script when written),
  `ordered-dithering.md`, `palettes.md`, `test-images.md`,
  `machine-screens/` (decided 2026-10-16, the user's idea: one folder,
  its `README.md` for what all cell screens share, which mode for which
  picture included, and one page per machine, `zx-spectrum.md` first,
  with the colors, attributes, file layouts and sources; mirrors
  `Puregrain.Cells` and `Puregrain.Machine.<Name>`; `c64.md` since
  2026-10-18),
  `gamma.md` (linear light for users: what `--gamma` does, which value for which
  view, measured, dark tones, gray first, machine screens, each client,
  the engine check, the cost; linked from the READMEs, and later from
  the web UI's (i)), `exact-arithmetic.md` (why the curves
  use roots of our own, how they're computed, neighbouring numbers, the
  light curves, the engine self-check),
  `benchmarks-dithering.md` (current),
  `benchmarks-fifo.md` (finished record). READMEs summarize and link
  rather than copy, so tables don't drift apart. The CLI README's
  "Machine screens" keeps only the CLI's part: options, the size rule
  (the CLI's size error points there for the resize hint), the files in
  a sentence each, and links.
- `scripts/measure-gamma.mjs` (2026-11-15) — dithers the test images
  through the real CLI under each gamma and measures the results in two
  views (blurred in light, as the eye at 1:1; blurred as stored, as a
  smoothing scaler), as CIE L* or CIELAB ΔE, plus the flat grays that
  come out black; the source of `docs/gamma.md`'s tables. Run after
  `npm run build`; pictures go to `samples/gamma/`.
- `cli/README.md` — the CLI's user docs, installing from npm first; its
  examples run it from a checkout (`npm run dither-cli -- …`).
- `npm/README.md` — the npm package's page (see `npm/` above), frozen
  per version (a fix shows with the next release).
- `web/README.md` — the web UI's user docs: running it, using it, its
  settings as CLI options, and the manual checklist.
- `web/ROADMAP.md` — the web UI's plan and its decisions with their
  reasons; it stays after the merge (decided 2026-11-01), since v3
  builds on them.
- `logo/README.md` — the logo's files, their use, and how it's made and
  made again; `logo/LICENSE.md`, its terms.
- `pictures/README.md` — the sample picture: what it shows, trying it
  (checkout, npm, the lab), where it comes from (the prompt), its
  license.
- `docs/similar-tools.md` — an internal working document, not linked
  from the README (the user, 2026-11-04): a survey of similar tools, the
  facts behind the positioning. Part 1, converters for retro machines
  (2026-11-03): puregrain is the narrowest, but alone in exactness
  across library, CLI and web, in an MIT library (Dithertron's is
  GPL-3.0) and in evidence for its recommendations. Part 2, general
  dithering tools and libraries, later.

## Core architecture

- **Module structure (reshape of 2026-10-04, `Dither.*` → `Puregrain.*`).**
  Guiding rule: *start closed, open later* — exporting more later is
  compatible, removing an export breaks users, so anything still an open
  API decision stays internal. Every module has an explicit export list.
  - Public: `Puregrain.Dither` (`ditherImage`, `ditherRows`, and the
    stepper `Dithering`/`initDithering`/`ditherRow`, each with a twin
    taking a gamma, `…With`), `.Kernel`, `.Pixel`, `.Quantize`,
    `.Palette`, `.Palette.Presets`, `.Ordered`, `.Gamma`, `.SelfCheck`.
  - `Puregrain` — a facade, re-exports only: what a typical application
    needs plus the types for signatures; building blocks for
    customization (`compilePalette`, `distance2`, `nearestColorFast`,
    `paletteColors`, `compileThresholdMap`, `bayerMatrix`, `thresholdAt`)
    stay in their modules. Docs recommend `import Puregrain as P`. The
    CLI imports the typical features only through `Puregrain`, so its
    build checks the facade covers a real application; the specialty
    modules, which stay out of the facade (`Puregrain.Cells`,
    `Puregrain.Machine.*`), it imports directly, as an application would
    (decided 2026-10-11).
  - `Puregrain.Internal.*` (`Fifo`, `Kernel` (compiled), `State`, `Step`,
    `Row`, `Image` (`ditherImageVia`, `ditherRowsVia`), `Quantize`,
    `Gamma`, `Exact`, `SelfCheck`, `Util`) — exported
    (PureScript has no package-private modules; the tests need them) but
    documented as unstable. `Fifo` and the backend-choosing drivers stay
    internal (decided 2026-10-05).
  - Public doc comments are self-contained (Pursuit shows them): no
    `CLAUDE.md`/test references, absolute GitHub links to `docs/`;
    dev notes go in plain `--` comments. Internal modules may point at
    repo docs. Convention for public functions (agreed 2026-10-15; pilot:
    `Puregrain.Cells`): a summary line; the arguments in signature order,
    one line each, type variables included (Pursuit shows types without
    parameter names, so prose names like `kernel` match nothing), except
    for a one-argument function whose summary names its argument; the
    result and how it fails; keep the code examples (users want them),
    and add one where it helps; rationale and background in `docs/` or
    plain comments. Applied to every public module on 2026-10-16; written
    down in CONTRIBUTING.md ("Doc comments").
  - The reshape was verified byte-identical: 17 CLI configurations
    produced the same PNGs before and after.
- `Puregrain.Kernel` — `Kernel` is an opaque, checked `Array Offset`
  (`{dx, dy, weight}`), the same pattern as `ThresholdMap`:
  `fromOffsets :: Array Offset -> Either String Kernel` checks that every
  offset points forward in scan order (`dy > 0`, or `dy == 0 && dx > 0`;
  unchecked, a backward/self offset crashed at the first pixel and
  `dy < 0` was silently dropped), every weight is finite, and no
  neighbour appears twice (rules 2–3 by "start closed": relaxing later
  is compatible). Weight sign and sum aren't checked (Atkinson's 3/4 is
  deliberate). `offsets` reads them back; presets `floydSteinberg`,
  `atkinson`, `jarvisJudiceNinke`, since 0.2.1 (2026-11-05) `stucki`,
  `burkes`, `sierra3`, `sierra2`, `sierraLite`, `fan`, `shiauFan` and
  `shiauFan2` (each table checked against at least two sources, listed in
  `docs/error-diffusion.md`; `KernelSpec` writes each table out as
  published, independently of the library), and `noDiffusion` (the empty
  kernel; `[]` is no longer a `Kernel`). Names (decided 2026-11-04):
  family first, the Sierras numbered by the rows they span, as FFmpeg and
  DitherPunk.jl number them (`sierra3`, CLI `sierra-3`, label "Sierra
  3"). Left out on purpose: Simple 2D (a teaching example), Stevenson–Arce
  (made for hexagonal grids) and False Floyd–Steinberg (worse, and its
  name confuses); the page's "Not included". The test generator draws distinct
  offsets per row, so its kernels always pass. `Puregrain.Internal.Kernel`:
  `CompiledKernel` (record: `currentOffsets`, `futureLayers`, `maxDepth`)
  is a precomputed cache built once via `compileKernel`, threaded through
  the hot path instead of recomputing `Array.filter`s per pixel
  (PureScript does NOT auto-memoize like GHC sometimes does — this bit us
  once as a real, measured regression).
- `Puregrain.Internal.Fifo` — `class Fifo (f :: Type -> Type)` with 4 methods:
  `replicate`, `enqueue`, `dequeue`, `replace` (shift-left-by-n +
  zero-fill, its own method rather than `drop`+`<>` because that
  composition is O(n) even when n is small — see below). Instances:
  `List.Lazy`, `Data.List` (strict), `Array`, `Data.CatQueue` (registry
  package `catenable-lists`: Okasaki's strict two-list queue).
  **`CatQueue` is the production default** (see Performance below). Its
  O(1) amortized `dequeue` assumes each queue version is used once
  (an old version used again redoes the list reversal) — which is how
  `step`/`stepRow` use them. At the row level, reuse costs nothing
  extra: stepping from an old state redoes that row's work, the
  reversal included, so public `Dithering` states are freely reusable
  (an earlier "use each state once" worry, corrected 2026-10-07).
- `Puregrain.Pixel` — `Gray = Number`; `RGB`/`RGBA` are `newtype`s (not
  `type` aliases — aliases sharing record shape would collide on
  instance resolution) with hand-written `Semiring`/`Ring` (honest
  `mul`/`one`, unused by diffusion but a legitimate algebra) and a
  custom `class Ring a <= Scalable a where scale :: Number -> a -> a`
  (kernel weights are always `Number` regardless of channel count), plus
  `class MapChannels` (+ `Number`/`RGB`/`RGBA` instances).
- `Puregrain.Quantize` — `Quantize a` is opaque: a newtype (in
  `Puregrain.Internal.Quantize` since 2026-11-14) over
  `Conversion a -> Context -> a -> a`, the driver's conversion to light
  first (linear light's decision 1), whose constructor isn't exported
  (decided 2026-10-05, "start closed"), with `type Context = { x :: Int, y :: Int }`
  (the pixel's position). Built by `quantize :: (a -> a) -> Quantize a`
  (position-blind) or `quantizeWith :: (Context -> a -> a) -> Quantize a`
  (uses the position; e.g. `Puregrain.Ordered`), run by `runQuantize`.
  Same power as the constructor, but users can't take one apart, so the
  representation may change (a position-blind flag to skip the
  per-pixel `Context`, a per-row setup) without breaking them. Helpers needing only some
  context fields take `forall r. { x :: Int | r }` (row polymorphism —
  PureScript's answer to Haskell's `HasX` classes), so `Context` can
  grow without breaking them. No Reader monad: a plain function of a
  record, by decision. The scalarED toolkit lives
  here too: `perChannel`, `nearestLevel`, `evenRamp`, `threshold` (see
  scalarED/vectorED below).
- `Puregrain.Palette` — vectorED: `CompiledPalette` (a `NonEmptyArray RGB`
  packed with a swappable distance metric, currently only `distance2`),
  `nearestColorFast`/`nearestColor`. `CompiledPalette` is opaque (read
  the colors with `paletteColors`): the palette search is the next
  performance target and may change its representation. Note `distance2` is plain RGB
  distance, not perceptual: pure green is nearer to black than to white
  (pinned by a test).
- `Puregrain.Palette.Presets` — fixed palettes as plain `NonEmptyArray RGB`
  (the caller picks the metric): `blackWhite`, `websafe216`, `cga16`
  (= EGA/VGA default; the Linux console's values, in ANSI order —
  verified in the kernel's vt.c; Wikipedia's terminal table has a
  display-adjusted "CGA/EGA/VGA" column, not these digital values),
  `ansi16`/`ansi256` (xterm's values — plain presets, deliberately no
  terminal-scheme parameter: the console/VGA colors are already
  `cga16`), `c64` (Colodore, see below), `zxSpectrum`
  (normal = 0xD8). Historical/terminal palettes have no official RGB, so
  every preset cites its source in a comment — values were checked
  against those sources, not recalled. Per-pixel; the ZX attribute cells
  and the C64's hires cells are `Puregrain.Machine.ZxSpectrum` and
  `Puregrain.Machine.C64` with `Puregrain.Cells`, and other
  block-constrained looks (C64 multicolor, pseudo-graphics) are a TODO.md
  item.
  User-facing reference: `docs/palettes.md` — keep it in step with the
  module (a new preset means a new row there and in cli/README.md's
  short table). `c64` switched from Pepto's 2001 values to Colodore on
  2026-10-17 (the user's decision): with the 2001 colors a test photo came
  out almost gray. Measured on it, even the best possible mixes of the
  2001 colors keep only 42% of its color (Colodore at VICE's settings
  77%, at the model's defaults 63%), and Atkinson's color error after
  blurring fell from 37.9 to 21.2 (29.3 with the defaults). The values
  are VICE's `colodore.vpl`, which is Pepto's model at brightness 47.5,
  contrast 100, saturation 70: verified by re-implementing the model from
  pepto.de/projects/colorvic (its defaults are 50/100/50) and searching
  the settings. Chosen over the defaults for the closer colors, a
  legitimate setting of the same model. VICE's *default* palette file is
  still Pepto 2001 (`pepto-pal`), so "what VICE shows" favors neither.
  Output with `c64` changes, so the next release is 0.2.0.
- `Puregrain.Ordered` — ordered (Bayer) dithering as an ordinary
  `Quantize Number`, over levels; color via `perChannel`. Pure ordered
  dithering = `noDiffusion`; with any other kernel it's the
  hybrid ("threshold modulation"): the error stays `corrected − q`,
  measured against the value, so diffusion keeps the tones and the map
  only places the dots. `ThresholdMap` is opaque, so every map is
  checked: built by `bayer n` (side, any power
  of 2 incl. 1; `Maybe`, one failure reason, like
  `compilePaletteFromArray`) or `compileThresholdMap` (ranks;
  `Either String`, several failure reasons the caller must tell apart).
  Thresholds `(rank + 0.5) / (maxRank + 1)`; `thresholdAt` takes any
  `{ x, y | r }` (row polymorphism, as planned for `Context` helpers).
  `ordered` sorts the levels once, decides `v − lo > t·(hi − lo)`
  (division-free), is total (clamps; a NaN can't loop), and
  `ordered (bayer 1)` ≡ `nearestLevel` on sorted levels. Against a
  palette (vectorED) it's not supported: TODO.md, and
  docs/ordered-dithering.md "Not supported".
- `Puregrain.Cells` (2026-10-11) — dithering with
  cells, like the attribute cells of 8-bit machines. Processed in
  *bands*, one row of cells at a time: per band, each cell gets the
  candidate (any type `c`; the mode's `palette` maps it to an opaque
  `CellPalette` of 1 or 2 colors, built by `singleColor`/`colorPair`)
  with the lowest score. A `CellMode c` record bundles what defines a
  screen mode: `size`, `palette`, `candidates` (decided 2026-10-15, in
  place of three separate arguments). A machine module exports one value
  per screen mode (`Zx.screen`); a variant is a record update
  (`Zx.screen { candidates = fewer }`). A marker typeclass for `c` was
  considered and rejected (2026-10-15): without methods it checks
  nothing, and a class with the palette method would allow only one
  mapping per type, where a function allows any (as `compilePalette`
  takes its distance as a function). After the choice, the band's rows are dithered (internal
  `stepRow`, with a quantizer built for that band, which reads the
  pixel's cell palette by index `x / cellWidth`). Inside the cells, an
  opaque `CellQuantizer` decides (2026-10-15): `nearestInCell`, the nearer
  color (with a kernel, error diffusion), or `orderedInCell map`, the
  second color where the pixel's fraction of the way from the first,
  along the line between them, is above the map's threshold at its
  position; division-free like `Puregrain.Ordered`, `>` (at a threshold
  stays the first, pinned). With `noDiffusion` that's pure ordered
  dithering, else the hybrid. The position counts from the image's
  corner, not the cell's, so any map size works (8 repeats in every 8 × 8
  cell, 16 spreads 257 tone steps over 2 × 2 cells); no restriction to
  sizes that divide the cell. An argument of `ditherCells`/`ditherBands`
  rather than a second pair of functions (decided 2026-10-15; changing
  the signature was free, `Puregrain.Cells` being unreleased). One engine
  (`stepBand`), two drivers, like `ditherImage`/`ditherRows`:
  `ditherCells` (in memory, returns `{ cells, image }`) and
  `ditherBands` (lazy: a band's rows are read only when the band is
  forced, so one band is in memory; returns `{ cells, rows }` per band,
  which a `.scr` writer needs). Choosing and dithering were first two
  public functions (`chooseCells`, `cellQuantize`; phase B); fused in
  phase B2 (decided 2026-10-11): one implementation, and a cell grid
  that doesn't match the image can no longer be passed. Exporting a
  "choose only" function later is compatible (e.g. for hand-fixed
  attributes). Cells are chosen from the *original* pixels, not a
  pre-dithered image (no information lost, no dot noise in the choice,
  independent of the kernel); in-memory and streaming results are
  identical, pinned by a property. The score: the sum of each pixel's
  squared RGB distance to the *segment* between the two colors, since
  dithering can produce any mix of them. (Scoring by the nearer color
  fails: a gray scores the same with black–white and blue–white, as the
  user pointed out.) Candidates are tried in the given order and the
  earlier wins a tie (`<`): the order is the caller's policy (ZX: single
  colors first, nearest pairs first, so the narrowest palette wins). Two
  early stops, at a score of 0 and when a sum reaches the best so far,
  give the same result: `CellsSpec` pins that against a plain full-score
  search, with exact ties (a duplicate candidate, images made of the
  candidates' own colors). The tie example alone doesn't catch a `<=`;
  the property does (mutation checked). `CellPalette` is a plain
  container: its two colors are symmetric for the choice and for
  `nearestInCell`; only `orderedInCell` uses their order (the pattern's
  direction: the first is the base, the second's dots come in as a pixel
  nears it). What they mean (ink, paper, BRIGHT) belongs to
  `Puregrain.Machine.<Name>`. Cell sizes below
  1 count as 1 (no positive-integer type: `naturals` includes 0 and
  clamps too); partial cells at the edges. Not in the facade (start
  closed). Laziness tests wrap *every* read in `errorOf`: a read that
  happens too early otherwise crashes the whole test run instead of
  failing that test (seen with a mutation, 2026-10-11).
- `Puregrain.Machine.ZxSpectrum` (2026-10-11) — the first module of the
  `Puregrain.Machine.<Name>` namespace (decided 2026-10-11: one module per
  machine, with its display rules; `C64`, `Msx` would sit next to it).
  Imported `as Zx`, with ZX names: `Attribute` (opaque, so only the 71
  valid values exist; read with `ink`, `paper` as color codes 0–7, and
  `bright`), `attributes`, `attributePalette`, `normalScreen` and
  `brightScreen` (2026-10-17: the 36 attributes without BRIGHT, or black
  and the 35 with BRIGHT, filtered from `attributes` so their order and
  tie rule hold), and `screen`, the
  `CellMode` with 8 × 8 cells (it replaced a separate `cellSize`,
  2026-10-15). The 71:
  per brightness 8 single colors and 28 pairs, minus the duplicate
  all-black cell (kept without BRIGHT). Convention as on the Spectrum
  (black ink on white paper): ink = the darker color (lower code), paper
  = the lighter; a single-color cell has ink = paper. Order (the tie
  policy for `Puregrain.Cells`): the 15 single colors first, then the
  pairs by the distance between their colors, nearest first (equal
  distances: normal before bright, then ink, then paper). The order is
  what makes "a picture made only of valid cells dithers to itself"
  hold: normal white lies on the black–bright white segment, so a cell of
  black and normal white scores 0 with both pairs, and the nearer must
  win (mutation checked: farthest-first breaks the property). Colors
  come from the `zxSpectrum` preset by index (it's in color-code order);
  `ZxSpectrumSpec` checks them against the code's bits (1 blue, 2 red,
  4 green), written independently. Not in the facade. `toScr`
  (2026-10-12) turns `ditherCells`' result, the record of cells and
  image, into a `.scr` file's 6912 bytes, `Either String (Array Int)`
  (the record, because that's what `ditherCells` returns; decided
  2026-10-12). `Left` for an image not 256×192, cells not 32×24, or a
  pixel not one of its cell's colors. The bitmap is built offset by
  offset, inverting the Spectrum's address formula; paper is tested
  first, so a single-color cell gets only 0 bits (only an example test
  catches ink-first: reading the file back can't see those bits). The
  spec's reader `readScr` uses the forward formula, with arithmetic, on
  random full screens (`quickCheck' 10`: each has 49,152 pixels).
  `toTap name` (2026-10-16) writes a `.tap`: a BASIC loader that starts by
  itself, `10 LOAD "" SCREEN$: PAUSE 0` (decided: emulators opening a
  tape type only `LOAD ""`, which skips a CODE file, and typing `SCREEN$`
  on a 48K is awkward), then the screen as a CODE file, 6980 bytes in
  all. Each file a header block and a data block: two-byte length, flag,
  bytes, XOR checksum. The BASIC line and its tokens follow the ZX
  Spectrum manual's chapter 24 and its character set (line number high
  byte first, the number 0 as its digit, 0x0E and five zero bytes); the
  sources are cited in the code. The name: up to 10 printable ASCII
  characters, else `Left`; it needs `Data.Char`/`Data.String`, so the
  library depends on `strings` since then. The spec's `readTape` walks
  the blocks independently, and check-cli's JavaScript reader compares
  the tape's screen with the same run's `.scr`.
- `Puregrain.Machine.C64` (2026-10-17/18, branch `c64-hires`) — the C64's
  hires bitmap mode, the second machine module, imported `as C64`. One
  module per machine, so the multicolor mode (a TODO.md item) would join
  it; the names leave room for it (no type called just `Cell`).
  `HiresCell` is opaque, so only the 136 valid values exist (read with
  `foreground` and `background`, color codes 0–15); `hiresCells`,
  `hiresPalette`, `hiresScreen` (the `CellMode`, 8 × 8). The 136: 16
  single colors and 120 pairs. The foreground (the 1 bits) is the darker
  color by luma, 0.299 R + 0.587 G + 0.114 B of the preset's values,
  since the C64's codes aren't in order of brightness; on an exact tie,
  the lower code. Seven pairs are nearly equal by the C64's design (green
  and light red); there the tiny difference decides, which only sets an
  ordered pattern's direction. Order as on the Spectrum: single colors
  first, by code, then pairs nearest first (spread, then foreground, then
  background). It keeps a picture of valid cells unchanged (grey lies on
  the black–white line); single colors first can't be guarded by that
  property (a single color is always an endpoint of a narrower pair), only
  by the ordering test (mutation checked). Colors come from the `c64`
  preset by index; `C64Spec` writes them out independently. Its name
  needed digits in test discovery. `toHiresPrg` (phase 3) writes a
  14,145-byte `.prg`: load address 2049; a five-line BASIC viewer there;
  the colors at 3072 ($0C00), foreground × 16 + background; the bitmap at
  8192 ($2000), cell by cell (byte (y/8)·320 + (x/8)·8 + y mod 8, bit 7 −
  x mod 8; the background is tested first, so a single-color cell gets 0
  bits); zeros between. The video chip reads the colors in place (53272 =
  3 × 16 + 8 = 56), decided 2026-10-17 over phase 0's plan, colors after
  the bitmap copied to 1024 by a BASIC loop (a few seconds of black
  screen, and the text screen overwritten). The viewer is BASIC, not 6502
  code, so it's readable and checkable: it notes 53280/53265/53272,
  blanks the screen, sets the border, turns
  bitmap mode on, empties the keyboard buffer (198), waits for a key, and
  puts everything back; the text screen is never touched. The border
  (2026-11-20, the user's idea; black from 2026-10-17 on, simple and the
  usual frame) takes the color most frequent along the picture's edge,
  its 1,036 outermost pixels, with the lowest color code on a tie, so
  black wins every tie it's in: it continues the picture rather than
  framing it. Not a C64 standard: the border is a register of its own,
  which picture files don't record, so each viewer chooses; this is our
  rule (`edgeColor`, from the cells, as the bitmap's bits are). A code of
  two digits lengthens line 20 by a byte, which shifts only the viewer's
  later lines: the colors and the bitmap stay at 3072 and 8192.
  `C64Spec` checks it against an independent count on random screens,
  with the ties and a two-digit code; check 11 against the PNG's edge
  (each mutation-checked). `C64Spec`'s
  `listing` walks the BASIC lines through their links with its own token
  table and rejects a keyword stored as plain letters (the C64 wouldn't
  run it); check-cli's check 11 does the same in JavaScript.
  `toArtStudio` (phase 4) writes Art Studio's 9009 bytes: load address
  8192, the bitmap, the colors, 7 zeros. Its layout was verified against
  RECOIL 6.4.5's own decoder (`DecodeIph` calls `DecodeC64Hires(content,
  2, 0x1f42)`), not just the docs.rs crate's "community knowledge";
  `readArt` and check 12 read it as RECOIL does. Both writers share
  `screenMemory` (the size checks, the bitmap, the colors; a `Left` names
  the caller), and `isGrid`/`sizeOf` moved to `Puregrain.Internal.Util`,
  shared with the ZX module. Checked by the user: the `.prg` in VICE's
  online version and in ty64 (ty64 defaults to Colodore, VICE to Pepto
  2001), the `.art` in RECOIL's web viewer (RECOIL's own C64 palette is
  Pepto 2001). User docs: `docs/machine-screens/c64.md`.
- `Puregrain.Gamma` (2026-11-14) — `Gamma` (opaque; defined in
  `Puregrain.Internal.Gamma`, with `Conversion`, `conversionFor`,
  `noConversion` and each curve's lazy table), the presets `gammaOff`,
  `gamma1p2`, `gamma1p5`, `gamma1p8` and `gammaSrgb`, `toLight` and
  `fromLight` (a pixel's color channels, through `Puregrain.Pixel`'s
  `ColorChannels`, alpha kept), and `toGray`. `Puregrain.SelfCheck`:
  `checkEngine :: Effect EngineReport`, `exactArithmetic` and `problems`
  (the digests in `Puregrain.Internal.SelfCheck`).
  `Puregrain.Internal.Exact`: the fifth and cube roots from exact
  operations. Specs: `ExactSpec`, `GammaSpec`, `InLightSpec` (the
  drivers and presets under every curve) and `SelfCheckSpec`. The
  decisions: "Linear light" under Key design decisions.
- No JS-facing layer exists right now (the npm package holds only the
  CLI), by decision: the old
  `Dither.Ffi` (a monomorphic `ditherImageArray` wrapper) was deleted
  once the JS CLI, its only user, was replaced by `puregrain-cli`. The
  npm interface gets designed fresh when the npm package work starts
  — JS can't call typeclass-polymorphic functions (they need instance
  dictionaries), so it will again be a monomorphic layer.
- `Puregrain.Internal.State` / `.Step` / `.Row` / `.Image` — diffusion
  core, polymorphic over `Fifo f` and `Ring a, Scalable a`. Public image
  type (decided 2026-10-06): `Puregrain.Dither.ditherImage` takes and
  returns `Array (Array a)` (in memory, strict) and `ditherRows` a lazy
  `List (Array a)` (streaming): `ditherImageWith`/`ditherRowsWith (Proxy
  CatQueue)`, two thin drivers (a strict `mapAccumL`, a lazy unfold) over
  one `stepRow`, pinned equal by a property in `DitherSpec`. No type
  aliases for rows or images (no safety, hides laziness, `Row` clashes).
  The stepper (decided 2026-10-07): `initDithering kernel quantize`
  builds an opaque `Dithering a` (compiled kernel, quantizer and a
  `DitherState CatQueue a` inside — the old `DitherAlgo` idea, settled
  without a public config record), and `ditherRow :: Dithering a ->
  Array a -> Either String { row, next }` dithers one row. A pure state
  machine: the caller runs the loop, so effectful sources (network
  streams, files) work; it caches nothing; states are reusable (undo).
  The generic `MonadRec` driver stays a TODO.md "future direction".
  `RowLayer f a = Array (f a)`, `DelayLine f a = Array (RowLayer f a)`.
  `current`/`matured`/`building` are row-local (`RowState`); only
  `delayLines`, the row counter `nextRow` and the image `width` (from
  the first row) cross row boundaries (`DitherState`). `stepRow`
  (internal, formerly `ditherRow`) checks each row's length against
  `width` first: a different length is a caller's bug, a `Left` with a
  message naming the row. The public stepper `ditherRow` returns it;
  `ditherImage`/`ditherRows` (and `Puregrain.Cells`' `ditherCells`/
  `ditherBands`) turn it into a runtime error with `orStop`, which lives
  next to `stepRow` in `Internal.Row` as the other half of its contract
  (moved from `Internal.Image` 2026-10-11), since their result types have
  no error channel. `ditherRowsWith`
  does all its work inside `defer`, so each row is read and dithered
  only when its cell is forced (until 2026-10-04 a strict `let` outside
  the `defer` dithered each row one cell early); `DitherSpec` pins it
  (an endless input; an input whose third row crashes when read). Positions: `y` is `DitherState.nextRow` (a caller
  stepping rows can't pass a wrong one); `x`/`y` ride in `RowState`, which `step` rebuilds per pixel
  anyway. Not `mapAccumLWithIndex`: on Array it's a generic default
  (`sequence <<< mapWithIndex`, an extra pass per row), while
  `mapAccumL` uses the native `traverse`.

## Key design decisions (with rationale)

- **Multi-channel model: scalarED vs. vectorED.** Two ways to dither a
  multi-channel pixel, distinguished *only* by how the quantizer is
  built — both are an ordinary `Quantize a` fed to the same, unmodified
  `ditherImage`; there is no separate pipeline per mode.
  - **scalarED** — each channel is an independent copy of the same
    scalar algorithm. Write a `Quantize Number` (e.g. `nearestLevel
    (evenRamp 4)`) and lift it with `perChannel` (via `class
    MapChannels`). The `Number -> Number` type is the guarantee: it
    only ever sees one channel's value, so it *cannot* couple channels
    — by construction, not by convention. Because `RGB`/`RGBA`'s
    `Ring`/`Scalable` instances are component-wise, one pass over an
    RGB image gives exactly what three separate grayscale passes over
    the channel planes would (property-tested in
    `Test.Puregrain.QuantizeSpec`).
  - **vectorED** — the quantizer sees the whole pixel at once, e.g.
    `Puregrain.Palette.nearestColor` (nearest palette color by a distance
    metric). Write the `Quantize a` directly on the composite type.
  - Channel *count* never changes mid-pipeline — reconsidered and kept
    (2026-09-23): a `Quantize a b` was rejected because `outErr =
    corrected - quantized` must stay in `a`'s `Ring` (the error has to
    live in the space future pixels are added in). Output-format
    reduction (e.g. RGB→Gray) is a plain post-hoc `map` over
    `ditherImage`'s result; image-dependent palette generation (e.g.
    median-cut) never happens inside `quantize`, which sees one pixel at
    a time: it's a step before dithering, whose palette the quantizer
    takes like a preset. First placed outside this library (FFI/caller
    side); reformulated with the user on 2026-11-05: an auxiliary part of
    the library, shared by the CLI and the web UI (TODO.md, "Palettes
    chosen from the picture"). Fixed preset palettes (e.g. `websafe216`)
    live inside it.
- **`DelayLine` is pre-padded to length `dy`, not grown from empty**:
  `initState` builds each `DelayLine` as `Array.replicate dy []` —
  already at its full, constant length `dy`, from the very first row
  (it has to be: `extractMatured`'s `Array.uncons` would crash on a
  truly empty `DelayLine`). What ramps up over the first `dy` rows is
  *content*, not length: each row pops one slot off the front
  (placeholder or real) and pushes one freshly-computed real layer
  onto the back, so it takes exactly `dy` rows for all `dy` original
  placeholders to be flushed out — the array's length never changes.
  An *empty* `RowLayer` (`[]`, a placeholder slot with zero fifos)
  contributes zero error for free, since `sumErrors [] = 0.0` — no
  placeholder/sentinel type needed. (We tried a `Constant | Real`
  sum-type wrapper for this first — real, measured per-pixel overhead
  from the extra allocation/unwrap; abandoned in favor of this.)
- **`replace` is a first-class `Fifo` method**, not `drop` + `<>`,
  because that composition is O(n) regardless of how small the drop
  count is (the `<>` walks the whole kept prefix). `CatQueue` does it
  as `skip` dequeues + `skip` enqueues: O(skip), and `skip` is at most
  the kernel's reach. (The former default, the finger tree `Seq`, used
  its O(log n) concatenation.)
- **`ST` doesn't fit the `Fifo` abstraction**: `enqueue`/`dequeue` are
  called from separate call sites across a value's lifetime (not one
  `runST` block), so real `O(1)` mutation there would require either
  unsafe linear-use assumptions or a hand-rolled consumed-flag +
  defensive-copy scheme — both rejected as not worth it given
  `CatQueue` already achieves the target asymptotic complexity. A genuinely
  mutation-based backend would need a different algorithm shape (one
  `runST` block per row/image), not a `Fifo` instance.
- **Linear light, `--gamma`** (2026-11-06 to 15, branch `linear-light`;
  released in 0.2.2). The spec, with every measurement, is in git
  history: `git show 861e67e:docs/linear-light-spec.md`. For users:
  `docs/gamma.md`; the arithmetic: `docs/exact-arithmetic.md`. Its
  decisions, numbered as in the spec (comments cite "linear light's
  decision N"):
  - **The choice and the default** (the user, 2026-11-12, replacing "on
    by default" of 2026-10-21): five curves, the same in the library, the
    CLI and the web UI: `off` (the default; the identity, not computed,
    so the results are the old ones bit for bit), `1.2`, `1.5`, `1.8`
    (light = (byte / 255)^γ) and `srgb`. Off by default, because linear
    light is right only where the dots reach the eye unsmoothed (1:1,
    from a distance), while scaling viewers (HiDPI, phones, pages)
    average stored values, where `off` is exact; and because dark tones
    turn black in the file as the gamma rises (Bayer 2 under `srgb`:
    every gray up to 99). In two views (`scripts/measure-gamma.mjs`),
    1.5 keeps the larger error smallest for every method, and the user's
    own view behaved like 1.0 to 1.5. The default may be revisited,
    perhaps per target. Every picture counts as sRGB: no profiles read.
  - **A wrapper around the whole dithering, not around the quantizer:**
    rows to light on the way in and back on the way out, the error in
    light and never converted, the targets converted once before the
    first pixel. Measured on a flat 128, Floyd–Steinberg to black and
    white: a wrapper around `quantize`, the error in stored values, gives
    50.0% white, as without it; the error in light 21.5%. An error can't
    be converted on its own (stored 20 → 30 adds 0.006 of light, 200 → 210
    0.067), and `imap` would decide on stored values, wrong for pure
    Bayer (50.0% against 21.9%).
  - **1, the API:** the plain drivers convert nothing and keep their
    types; the twins take the `Gamma` first (`ditherImageWith`,
    `ditherRowsWith`, `initDitheringWith`, `ditherCellsWith`,
    `ditherBandsWith`; `ditherRow` needs none, the state holds it), and
    the internal drivers became `ditherImageVia`/`ditherRowsVia`.
    `Quantize` gets a `Conversion` (both directions and the curve) from
    the driver once per run, through `quantizerFor`: passed per pixel,
    the targets would be converted per pixel. `quantizeInLight` hands the
    author the curve, to convert coefficients in the outer `let`;
    `quantize`/`quantizeWith` keep stored values in and out, at two
    conversions per pixel; `runQuantizeWith` runs one for a stored
    value. No tag on `Quantize` for a quantizer that ignores its curve
    (a mismatch could only crash: no error channel). Only the twins need
    `ColorChannels`, a class of its own, since `MapChannels` maps alpha.
    No constructor for other curves (start closed: the self-check
    couldn't vouch for them; one would check its two functions as
    inverses, rising, keeping 0 and 255). Compatible: 0.2.2, not 0.3.0.
  - **2, exact on every engine** ("the same results everywhere" can't be
    traded off, the user, 2026-11-08): `Math.pow` in Node 22 and in the
    browsers differed on about a tenth of the conversions. Roots of our
    own from exact operations, in PureScript, not FFI (the library stays
    free of JavaScript; `Puregrain.Internal.Exact`); one table of 256
    values per curve, built lazily on first use (at module load, even
    `--help` would pay); every target goes back through the table, so
    every byte comes back exactly; negative values mirrored, as CSS Color
    4's sample code does. The self-check, `checkEngine`, in `Effect` (a
    pure value could be shared or moved by an optimizer): eight stored
    digests, one per curve and direction, and every byte back from its
    light. A digest changes only on purpose, in the same commit, with a
    CHANGELOG line. No native path even where `Math.pow` would match.
  - **3, choices on stored values, amounts of light in light:** the
    nearest level and palette color are chosen on stored values (closer to
    OKLab for 6 of 7 palettes, and for 2 levels on 228 of 256 grays
    against 168; and `websafe216` = `--levels 6` needs both measured
    alike); the error and ordered dithering's share are light.
    `nearestLevel` compares with the sRGB midpoints converted to light (no
    cost per pixel); a palette brings each pixel back, table first.
    Levels and thresholds stay bytes: a threshold is converted, so
    `--threshold 100` cuts at gray 100 under every gamma (a cut at half
    the light was measured and rejected, 2026-11-12); levels even in
    light were rejected (L* error 1.79 against 0.88, uneven-looking
    steps; 2026-11-13). Under a curve, levels that aren't whole numbers
    are rounded to bytes, and of equal levels only the first is kept.
  - **4, gray:** `toGray`, luma on stored values with `off` (the classic,
    the old bytes), luminance (0.2126, 0.7152, 0.0722) on the curve's
    light otherwise: saturated colors lighter (blue 29 → 76), skin and
    sky barely changed, neutral pixels exact. It returns a stored value,
    which costs color pictures turned gray under a curve about a quarter
    more.
  - **5, machine screens:** the cells chosen on stored values;
    `orderedInCell` measures in light, `nearestInCell` decides on stored
    values; the error in light; exact for byte colors. Recommended `off`
    (a curve: up to 31% closer at 1:1 on the ZX Spectrum, 4–6% on the
    C64, 17–96% worse when scaled).
  - **6, the web UI's fit and flattening** mix in the curve's light (with
    `off`, the integer loops unchanged), back to a byte by the half-steps
    `toLight(b + 0.5)` (the user's choice over `fromLight` and
    rounding): one setting for every step that mixes colors. The CLI's
    future `--background` and `--fit` follow the same rule.
  - **7, names:** `--gamma` with `off` (`1.0` alone could read as
    "already linear", as in color management); `gamma1p2`… ("p" for the
    point: a name can't hold a dot, no underscores, no Unicode
    look-alikes); `toLight`/`fromLight`; `checkEngine` (the JavaScript
    engine) in `Puregrain.SelfCheck`, a module of its own since OKLab's
    arithmetic would join its report; not `Puregrain.Engine…`, the
    project's word for its dithering core. The facade has `Gamma`, the
    presets, the twins and `toGray`; `toLight`, `quantizeInLight` and
    the self-check stay in their modules.
  - **Cost:** `srgb` about ×1.34 at 1024² in the median, the palette ×1.4
    to ×2.0 (`docs/benchmarks-dithering.md`, 2026-11-15). **Later, on
    top:** OKLab or CIELAB distances, color profiles (TODO.md).

## Performance (history + charts: `docs/benchmarks-fifo.md`; current baseline: `docs/benchmarks-dithering.md`)

Root cause found and fixed: `Data.List.Lazy`'s `snoc` is O(n), so
accumulating a row's worth of diffused error (`building`, up to
`width` `enqueue` calls) cost O(width²) per row → O(width³) total for
square images — confirmed empirically (growth ratio → 8× per side-
doubling) before the fix, → 4× (i.e. `O(width×height)`, optimal) after
switching the default `Fifo` backend to `Seq`. ~38× speedup at
1024×1024. `Array` was benchmarked too (native memcpy-speed constants
beat asymptotics at tested sizes, ≤1024) — worth re-testing at larger
N since its growth-ratio trend was climbing back toward cubic.

2026-10-03: `Seq` (from a git fork of `sequences`, which blocked
publishing) was replaced by `Data.CatQueue`: ~3.6× faster again
(median over configurations; JJN ~6×), and the library now depends
only on registry packages. With the queue no longer dominant, the RGB
arithmetic and the palette search are the next costs
(`docs/benchmarks-dithering.md`).

2026-10-10: purs-backend-es (an optimizing backend, `output-es/`) gave
only ×0.92 in the median (websafe216 ×0.77, Floyd–Steinberg with a
threshold ×0.99): the hot path is polymorphic over `Fifo f`/`Ring a`
(dictionaries known only at runtime) and allocation-heavy, which no
backend fixes. The CLI keeps the purs build; the tooling stays
(`npm run build:es`, `--builds`). The ST test reference, compiled with
plain purs, is 2.6× faster than `ditherImage` at 1024² and flat up to
2048²: the design, not the backend, is the lever (TODO.md, "ST-based
diffusion").

## Testing

`Test.Puregrain.Reference` — an independent, deliberately naive
`ST`-based two-loop reference implementation (no `Fifo`/padding
machinery), used as a QuickCheck oracle. `Test.Puregrain.Arbitrary`
generates random `Kernel`s and images. `Test.Puregrain.DiffusionMechanicsSpec`
checks every `Fifo` backend against the reference on random inputs —
this is what actually caught real bugs (see Gotchas below), where
hand-picked example kernels (Floyd–Steinberg, Atkinson, JJN — all
`maxDepth ≥ 1`) did not.

Coverage was measured once (2026-11-17, the user's idea), outside the
repository, and is deliberately not tooling: the property tests and the
mutation checks say more about the tests' strength. What works: `c8`
(12.0.0) running the compiled `Test.Main` in Node, read per compiled
module (`output/<Module>/index.js`). What doesn't: mapping back to
`.purs` through the compiler's source maps (`purs compile -g
js,sourcemaps`, called directly, since spago refuses `--codegen`):
every file came out at 100%, the dependencies too. Most uncovered code
is noise: newtype constructors (the code uses `coerce`), superclass
accessors, the compiler's "Failed pattern match" throws, and our own
defensive crashes. Its real findings got tests the same day, each
mutation-checked: `RGBA` was never dithered (a four-planes property in
`QuantizeSpec`), `mul` of `RGB` and `RGBA` never ran (`PixelSpec`),
and `Internal.Gamma`'s formulas and table were never called with
`gammaOff` (`GammaSpec`). Left alone: the self-check's digest branches
for NaN and infinity, which its finite reference inputs never reach.

Library specs are flat `Test.Puregrain.<Name>Spec` modules, one per
module tested (e.g. `PixelSpec`, `QuantizeSpec`, `RowSpec`). `Test.Main`
discovers them with `^Test\.Puregrain\.[A-Za-z0-9]+Spec$` (digits since
2026-10-17: with letters only, a `C64Spec` would silently never run): spec-discovery
runs an unanchored `RegExp.test` over the shared `output/`, and the
anchors plus the single name segment keep out the CLI's
`Test.Puregrain.Cli.*` specs, which the CLI lists explicitly.

The documented exact checks (docs/test-images.md → "Exact checks") are
deliberately tested twice, at two levels: as Spec properties over
arbitrary kernels/palettes/images ("whole images" blocks in
`PaletteSpec`/`PixelSpec`/`OrderedSpec`/`ZxSpectrumSpec`/`C64Spec`), and end to end through the real CLI on the
generated images (`npm run check:cli`). Not redundant: Spec can't
reach the CLI's plumbing (PNG I/O, gray/RGB routing, launcher);
check:cli can't cover arbitrary inputs.

Visual checks and benchmarks share one set of generated images:
`scripts/generate-images.mjs` (drawing code only in
`scripts/lib/test-patterns.mjs`), documented tile by tile in
`docs/test-images.md`. Generated images go to gitignored `samples/`;
the two doc previews in `docs/images/test-images/` are the only ones
committed (refresh: `npm run docs:images`). `npm run generate-images`
writes both composites at 512², and the color one at 256×192 (the ZX
Spectrum's screen) for `npm run dither:zx`: Bayer 2 inside the cells as
a PNG, a `.scr` and a `.tap`, and Bayer 4 and Atkinson as PNGs, to
compare. Likewise at 320×200 (the C64's hires screen) for
`npm run dither:c64`: Bayer 2 as a PNG, a `.prg` and an `.art`, and
Bayer 4 and Atkinson as PNGs. The recommendation since 2026-11-03 (the
user found 2×2 more authentic): Bayer 2 for the look of the time, Bayer
4 for smooth tones, Atkinson for photos with fine detail; 8 and 16 stay.
Measured: in 300 real ZX loading screens (ZXDB's 150 most voted games of
1982–1989 and 150 more at random, through the ZXInfo API; the method in
a short note in docs/machine-screens/README.md), 2×2 patterns fill areas
in 22 screens, 4×4-only ones in 4, 8×8-only ones in none, and 95% of
the two-color cells are drawn by hand; after blurring, Bayer 4 keeps the
tones as well as Bayer 8, Bayer 2 like Atkinson. The C64 follows by
analogy, uncounted, and the docs say so. Before, Bayer 8 had been
chosen by eye on the test composite (2026-10-15 over Bayer 4 and
Atkinson; for the C64 on 2026-10-18, when after blurring Bayer 8,
Bayer 4 and Atkinson kept the tones equally well, 25.7/25.7/26.0, while
Floyd–Steinberg and the Bayer 8 hybrid streaked, about 35). Two steps, `--palette zx15 --kernel atkinson` and then
`--machine zx-spectrum --kernel none`, are mentioned briefly as an
alternative worth trying for photos (2026-10-17, the user's find), not
as a recommendation: measured after blurring, they keep the tones least
faithfully of the valid variants. Atkinson crushes dark and light tones (the sphere's shadow
turns black); with Floyd–Steinberg the ZX output shows streaks (error a
cell can't use builds up; calmer diffusion in cells is a Future
directions idea in TODO.md). One script per machine, with its best mode; the CLI's default kernel stays Floyd–Steinberg for
every mode (no per-mode defaults, decided 2026-10-12), except `--bayer`,
where the kernel picks the method (none, since 2026-10-14). A tile may be left out of every composite and only
rendered alone: `color:zx-cells` (valid ZX cells, which line up with the
8×8 grid only from the image's corner; its 71 attributes written out in
JS independently of the library) is the exact-check input for
`--machine zx-spectrum`, and `color:c64-cells` (all 136 hires cells,
Colodore's colors written out in JS; 2026-10-17) for `--machine c64-hires`,
at 320×200; `--list` marks such tiles "(alone only)". The two share their
drawing; since 136 is a multiple of the 4 cell patterns, each hires cell
always gets the same pattern (the ZX's 71 cycle through all four), which
the exact check doesn't depend on.
pngjs gotcha: the output
PNG color type must be passed to `PNG.sync.write(png, { colorType })`
— the `new PNG({ colorType })` constructor option is ignored by the
sync writer, which silently wrote every "grayscale" image as RGBA.

## PureScript gotchas hit during development (worth remembering)

- **`where`/`let` bindings are strict**, evaluated before the body: a
  check in the body runs after them (`stepRow`'s row-length check
  first ran after the row had already crashed), and a lazy-list cell
  built after a `let` doesn't delay that `let`. Put the work in the
  branch or the `defer` that should guard it.
- **In an `Effect` do-block, a leading `let` is evaluated when the
  effect is built, not when it runs** (`do let x = e; …` is just
  `let x = e in …`), so `try` can't catch an error it throws. Delay it
  behind a bind: `pure unit >>= \_ -> pure (f unit)` (`whenRun` in
  `Test.Puregrain.Util`, with `errorOf` and `mentions`).

- **A `where` after guards belongs to the last guard only** — unlike
  Haskell, where it scopes over all of them. `f n | c = g n | otherwise
  = h where g = …` fails with "Unknown value g" in the first guard.
  Use `if`/`case` instead, or put the shared bindings in a `where` of an
  unguarded equation (as in `Puregrain.Ordered.bayerMatrix`).
- **A pattern binding in a `where` or `let` sees only the bindings above
  it**: `{ width, height } = … roundedRatio …` with `roundedRatio`
  defined further down fails with "Unknown value roundedRatio" (seen in
  `Puregrain.Web.Prepare`, 2026-10-25). Define the helper first, or at
  the top level.

- **`(..)` is NOT empty when reversed**: `1 .. 0` evaluates to `[1, 0]`
  (descending), NOT `[]` like Haskell's `[1..0]`. This caused a real,
  QuickCheck-caught bug whenever `maxDepth == 0` (a legitimately valid
  kernel with no cross-row diffusion). Fixed via `Puregrain.Internal.Util.safeRange`
  — use it, not raw `(..)`, anywhere the upper bound can legitimately
  be less than the lower bound.
- **spago 1.0.4 calls a successful publish an error:** "Registry did not
  like this and answered with status 201" (it accepts only 200; the
  registry now answers 201 Created with a `jobId`). Fixed in spago PR
  #1417 (merged 2026-08-17), not released as of 2026-10-10. Never publish
  again on that message: check `https://registry.purescript.org/api/v1/jobs/<jobId>`
  (`"disposition": "published"`, `"success": true`). Hit at the 0.1.0
  release. And `spago registry info <pkg>` reads a cached index: add
  `--refresh` right after a publish.
- **spago rewrites `spago.yaml` in its own format** whenever it changes
  the file (`--ensure-ranges`, `spago install`): e.g. it wraps a long
  `description` over several lines (same YAML value). Commit its
  formatting, or release check E (`--ensure-ranges` changes nothing)
  fails although no range is missing. Hit 2026-10-09, after the
  one-line `description` was added; spago's wrapped form is stable.
  `--ensure-ranges` also *raises every existing lower bound* to the
  package set's version whenever the set moves, not only adding missing
  ranges (seen 2026-10-20, set 81.4.0 → 81.9.0: `prelude >=6.0.2` became
  `>=6.0.3`). Decided then (the user agreed): commit the raised bounds,
  with a CHANGELOG line, so the minimum versions are the ones we build
  and test with, as spago intends; the alternative, keeping lower
  bounds and checking for missing ranges some other way, would claim
  versions no longer tested. Before raising them, check the new
  versions' compilers (`spago registry info <pkg>`); for 81.9.0 they
  were unchanged, 0.15.0–0.15.16. A package-set update is its own
  change on `master`, checked by `check:clean` and byte-identical CLI
  outputs. Done so again on 2026-11-23, in between serpentine's phases:
  81.9.0 → 83.3.0, which needs purs 0.15.17 (82.0.1 was the last for
  0.15.16). Only 3 of our 97 locked packages changed, alike in 82.0.1
  and 83.3.0 (`integers` and `spec-discovery` patches, `free` a minor,
  the lab's): the two major set bumps touched none of ours (compared in
  `~/.cache/spago-nodejs/registry/package-sets/<version>.json`, offline).
  `--ensure-ranges` raised only `integers` to 6.0.2, with the same
  compilers, 0.15.0–0.15.17.
- **purs 0.15.17's npm installer needs a newer Node** (2026-11-23):
  `purescript-installer` 0.4.0 (with `undici` 8) wants Node `^22.22.2 ||
  ^24.15.0 || >=26.0.0`, and on 22.14.0 its postinstall crashed
  (`createZstdDecompress` is missing); npm rolled the install back. The
  user's machine moved from Node 22.14.0 to 22.23.5 (nvm; the globals
  `pnpm` and `purescript-language-server` reinstalled with it, npm pinned
  to the same 11.21.0, since `allowScripts` needs npm 11, while Node
  22.23.5 brings npm 10.9.9); 22.14.0 stays installed. Node alone changed
  none of the 23 compared CLI outputs. CI's `node-version: 22` takes the
  latest 22.x anyway. A shell started before the switch (an editor, a
  Claude Code session) keeps the old PATH: `nvm use default` there.
  Benchmarks from then on run on 22.23.5 (each section records its Node).
- **npm install scripts (`allowScripts` in `package.json`, 2026-10-09):**
  npm 11 warns about dependency install scripts not listed there, and its
  docs say they're blocked by default (npm 11.21 still ran them, checked
  2026-10-09). `purescript` must stay approved, by name without a version
  pin: its postinstall downloads the compiler, and the published package
  holds only a 348-byte placeholder `purs.bin` that prints "installation
  failed". `ssh2` and `cpu-features` (spago's, for SSH keys in
  `spago auth`) are denied: their scripts only build optional native code.
  Change with `npm install-scripts approve/deny <pkg>`.
- **`spago build --strict` only reports warnings for modules it compiles.**
  A module compiled earlier by a non-strict command (e.g. `spago test`)
  isn't recompiled, so its warning goes unreported: a strict build
  failed, `spago test` passed, and the next strict build passed too, with
  the same unused import still there (2026-10-11). Only a build from
  scratch is reliable: `npm run check:clean`, like CI.
- **No automatic memoization**: unlike GHC, PureScript never shares
  repeated pure computations for you. If something is computed inside
  a per-pixel hot path but doesn't depend on the pixel, hoist it out
  explicitly (see `CompiledKernel`).
- Several library API guesses were WRONG during development
  (`Data.List.replicate`, `chooseFloat` vs `choose`, etc.) — when
  unsure of an exact current signature, check rather than assume;
  this project's history has repeated real mismatches between assumed
  and actual APIs.

## Working style established in this project

- The workflow rules — branches (`master`, short-lived branches only for
  risky work, a long-lived one only as an exception decided with its own
  rules), CI, versions, releases — are in `CONTRIBUTING.md`; follow
  them. `npm run check` runs what CI (`.github/workflows/ci.yml`) runs:
  build with `--pedantic-packages --strict`, the test suites,
  `check:cli`, the npm package's build and `check:npm` (which needs the
  network), then the web UI's bundle and `check:web` (which needs
  Docker). Keep the two in step.
- **0.1.0 was published on 2026-10-10:** tag `v0.1.0`, registry job
  `65ff05b2-b62c-477c-b1f6-282a92ff9c21` (log: https://registry.purescript.org/api/v1/jobs/65ff05b2-b62c-477c-b1f6-282a92ff9c21),
  docs on Pursuit within a minute, GitHub Release created by CI. Pursuit
  shows the `Puregrain.Internal.*` modules too (they're exported; their
  docs say they're unstable).
- **0.1.1 was published on 2026-10-16** (22:00 UTC): tag `v0.1.1`,
  registry job `4b94254f-18a1-42d9-b095-55aab76afdaf` (log:
  https://registry.purescript.org/api/v1/jobs/4b94254f-18a1-42d9-b095-55aab76afdaf),
  docs on Pursuit within a minute, GitHub Release created by CI. Contents:
  `Puregrain.Cells` and `Puregrain.Machine.ZxSpectrum` (see CHANGELOG.md).
  The job finished about a minute after the upload: the docs and the
  compiler matrix come after "Successfully uploaded package to the
  registry", so check `finishedAt` and `success` before calling it done.
- **0.2.0 was published on 2026-10-18** (22:55 UTC on 2026-10-17): tag
  `v0.2.0`, registry job `2b741211-8c04-4a35-a2d8-72ca1dbf5ed4` (log:
  https://registry.purescript.org/api/v1/jobs/2b741211-8c04-4a35-a2d8-72ca1dbf5ed4;
  finished after 34 s, `success: true`), CI green on `master` and on the
  tag, GitHub Release created by CI, docs on Pursuit (the
  `Puregrain.Machine.C64` page included). Without a job ID, `spago
  registry info puregrain --refresh` also confirms a finished publish:
  the version is listed with its `publishedTime` and a filled compiler
  matrix (0.15.0–0.15.16), which the job adds only at its end. Contents: `Puregrain.Machine.C64`,
  `Zx.normalScreen`/`brightScreen`, and the `c64` palette switched to
  Colodore, which changes output and so made it 0.2.0, not 0.1.2 (see
  CHANGELOG.md).
- **0.2.1 was published on 2026-11-05** (17:42 UTC): tag `v0.2.1` on
  `e24c0a4`, registry job `ea92db01-a13f-4e45-8179-3e6bc7c15837` (log:
  https://registry.purescript.org/api/v1/jobs/ea92db01-a13f-4e45-8179-3e6bc7c15837;
  finished after 33 s, `success: true`; its log says "Successfully
  uploaded package docs to Pursuit"), CI green on `master` and on the
  tag, GitHub Release created by CI. Contents: the eight kernels of
  `docs/error-diffusion.md`, the raised minimum versions (package set
  81.9.0), and a new registry description (the 11 kernels and the
  machine screens), committed after the merge, so the published commit
  is `e24c0a4`, not the merge's `c9cf2f0`. New since 0.2.0: the registry
  runs the compiler matrix as separate jobs, queued at the publish job's
  end, so right after the publish the metadata listed only 0.15.0,
  0.15.2–0.15.5 and 0.15.16 (a partial matrix no longer means an
  unfinished publish: check the job); and Pursuit sits behind Anubis bot
  protection, which refuses automated fetches ("Access Denied"), so the
  docs were confirmed from the job's log, and a browser shows them.
- **0.2.2 was published on 2026-11-16** (20:32 UTC): tag `v0.2.2` on
  `ec1d2ee` ("Release 0.2.2", after the merge commit `bddd468` of PR #9,
  the branch `linear-light`), registry job
  `d97d4752-ccba-4421-8cc3-021ddfd8edab` (log:
  https://registry.purescript.org/api/v1/jobs/d97d4752-ccba-4421-8cc3-021ddfd8edab;
  finished after 44 s, `success: true`, "Successfully uploaded package
  docs to Pursuit"), CI green on `master` and on the tag, GitHub Release
  created by CI, the lab v2.3 on Pages with 0.2.2. Contents: linear light
  (`Puregrain.Gamma`, `Puregrain.SelfCheck`, the `…With` drivers,
  `quantizeInLight`, `runQuantizeWith`, `ColorChannels`), compatible, so
  a patch version. The matrix jobs were queued for 0.15.0 and 0.15.2 to
  0.15.17, the last a compiler newer than the 0.15.16 we build with.
  GitHub's merge button offered only squash: "Allow merge commits" was
  off in the repository's settings, and was turned on for PR #9.
- **0.3.0 was published on 2026-11-21** (23:19 UTC), the first release
  with the npm package: tag `v0.3.0` on `5ed8f0c` ("Release 0.3.0"),
  registry job `5e001467-599a-4726-adf0-3741e79bb8a8` (log:
  https://registry.purescript.org/api/v1/jobs/5e001467-599a-4726-adf0-3741e79bb8a8;
  finished after 32 s, `success: true`, docs on Pursuit), GitHub Release
  created by CI. A minor version because the C64 `.prg` border changes
  output; also the CLI on npm, `--version`, the name `puregrain`. npm:
  `puregrain@0.3.0` published by the user at 23:53 UTC (67.1 kB packed,
  shasum `99a5fd59…`), confirmed with `npx puregrain@0.3.0 --version`
  from an empty folder. Learned on the way: `npm publish npm/dist` reads
  the path as the GitHub repository `npm/dist` (`./npm/dist` is right);
  npm refuses to publish without two-factor authentication, and its
  settings offered only a security key (a passkey, on a phone or in a
  password manager), with the publish then confirmed in the browser; and
  npm first showed a placeholder version, `0.0.0-stage`, as `latest`,
  with 0.3.0 there about a minute later (the placeholder stays in the
  version list).
- Releases (decided 2026-10-07): `spago publish` checks a clean tree,
  the tag against `publish.version` and the version ranges, then
  **pushes the tag itself** right before calling the registry (verified
  in spago 1.0.4's code; it warns against pushing the tag earlier). So
  CI on a `v*` tag can't stop a publish: the checks A–F run locally
  first (`npm run release:check -- X.Y.Z`), and CI on the tag repeats
  them (`--skip-check` for A, which the job has just run) and creates
  the GitHub Release (`--notes`). Hence no separate `release.yml`. No
  registry/Pursuit account is needed: publishing is unauthenticated;
  SSH-key `owners` only matter for unpublish/transfer. Version ranges:
  keep them, `release:check` fails if a dependency lacks one.
  Once a package is in the registry, **a pushed version tag publishes
  itself**: the registry's daily importer (07:00 UTC, `DailyImporter.purs`
  in registry-dev, verified 2026-10-08) publishes every unpublished
  version tag of its GitHub packages that points to a commit from the
  last 24 hours. The same daily jobs add new versions to the package
  set if they compile with it, so `spago install puregrain` works in
  package-set projects from the day after a release.
- **Dashes (decided 2026-10-08):** code — string literals, test names,
  messages, config values such as `spago.yaml`'s `description` — uses
  only the ASCII hyphen `-`: in ranges (`0-255`), name pairs
  (`Floyd-Steinberg`), and ` - ` where a sentence would take a dash.
  Comments (doc comments included) and `.md` files may keep typographic
  dashes: `–` for ranges and name pairs, `—` as punctuation. Why: an en
  dash looks like a hyphen, so searches and copied names silently
  mismatch, and code is what people type, search and copy. (Other
  symbols such as `×`, `²`, `→` and the block characters of the
  examples' text art are fine anywhere.)
- Go slow, one architectural change at a time; confirm before moving
  to the next step on anything non-trivial.
- Don't add generality/abstraction ahead of a concrete, current need
  (YAGNI was invoked repeatedly and correctly) — e.g. `Pixel`
  generalization was deliberately deferred until color dithering was
  the actual next task, not done speculatively earlier.
- Benchmark before optimizing, and document benchmark results with a
  reproducible method + chart, including negative/regression results,
  not just wins. New runs go in `docs/benchmarks-dithering.md` as a
  new dated section (`npm run bench`, chart via
  `scripts/plot-benchmarks.mjs`); `docs/benchmarks-fifo.md` is the
  finished record of the `Fifo` investigation and isn't extended.
