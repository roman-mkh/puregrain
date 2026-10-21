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
  covers the library and the CLI); `package.publish` in `spago.yaml`
  holds the license and the current version (0.2.0), and
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
  them. `--kernel none` is the empty kernel. `--bayer N` (2–16) is its own
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
  tones), with the fewest neighbours of the kernels that do, and it's the
  classic. `--machine NAME`
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
  `spago test` runs both packages' suites (library, then CLI).
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
  for square pixels, every line within 80 columns.
- **`puregrain-web`** (`web/spago.yaml`, `web/src/`, modules
  `Puregrain.Web.*`; since 2026-10-20, on the long-term branch `web-ui`)
  — the web UI, the library's second real client, in Halogen. Its plan,
  decisions and open questions are in `web/ROADMAP.md`; its architecture
  and gotchas in `web/CLAUDE.md`, which Claude Code reads when working
  in `web/`; its user docs, with a manual checklist, in `web/README.md`.
  `npm run web:build` bundles it into `web/dist/` (gitignored),
  `npm run web:serve` serves that on localhost:8000. The workspace's
  strict build compiles it, so a library change that breaks it fails
  `npm run check` and CI. Version 1 (functional, not styled) was done on
  2026-10-21: loading, the settings, dithering in a worker with progress
  and cancelling, the split view, the PNG download.
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
- `CHANGELOG.md` — the library's changes per version; new entries go
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
  changes, refresh the excerpt**. A script checking the copy was
  considered and dropped (2026-10-08): more machinery than a 15-line
  excerpt needs. The program's printed output isn't shown (dropped
  2026-10-08): text art made for a dark terminal looks inverted on light
  pages (Pursuit, GitHub's default), and Pursuit's code font (Roboto
  Mono) probably lacks the block characters, so a fallback font could
  misalign them. The README says in words what the terminal shows.
- `examples/README.md` — the example programs: what each shows, how to
  run them, a REPL session with variations to try.
- Reference docs live in `docs/` and are the single source of truth:
  `ordered-dithering.md`, `palettes.md`, `test-images.md`,
  `machine-screens/` (decided 2026-10-16, the user's idea: one folder,
  its `README.md` for what all cell screens share, which mode for which
  picture included, and one page per machine, `zx-spectrum.md` first,
  with the colors, attributes, file layouts and sources; mirrors
  `Puregrain.Cells` and `Puregrain.Machine.<Name>`; `c64.md` since
  2026-10-18),
  `benchmarks-dithering.md` (current),
  `benchmarks-fifo.md` (finished record). READMEs summarize and link
  rather than copy, so tables don't drift apart. The CLI README's
  "Machine screens" keeps only the CLI's part: options, the size rule
  (the CLI's size error points there for the resize hint), the files in
  a sentence each, and links.
- `cli/README.md` — the CLI's user docs.
- `web/README.md` — the web UI's user docs: running it, using it, its
  settings as CLI options, and the manual checklist (on the `web-ui`
  branch until the merge).

## Core architecture

- **Module structure (reshape of 2026-10-04, `Dither.*` → `Puregrain.*`).**
  Guiding rule: *start closed, open later* — exporting more later is
  compatible, removing an export breaks users, so anything still an open
  API decision stays internal. Every module has an explicit export list.
  - Public: `Puregrain.Dither` (`ditherImage`, `ditherRows`, and the
    stepper `Dithering`/`initDithering`/`ditherRow`), `.Kernel`, `.Pixel`,
    `.Quantize`, `.Palette`, `.Palette.Presets`, `.Ordered`.
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
    `Row`, `Image` (`ditherImageWith`, `ditherRowsWith`), `Util`) — exported
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
  `atkinson`, `jarvisJudiceNinke`, and `noDiffusion` (the empty kernel;
  `[]` is no longer a `Kernel`). The test generator draws distinct
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
- `Puregrain.Quantize` — `Quantize a` is opaque: a newtype over
  `Context -> a -> a` whose constructor isn't exported (decided
  2026-10-05, "start closed"), with `type Context = { x :: Int, y :: Int }`
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
  blanks the screen, sets a black border (decided 2026-10-17: simple, the
  usual frame; matching the picture's edge is a TODO.md idea), turns
  bitmap mode on, empties the keyboard buffer (198), waits for a key, and
  puts everything back; the text screen is never touched. `C64Spec`'s
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
- No JS-facing layer exists right now, by decision: the old
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
    median-cut) happens *outside* this library (FFI/caller side).
    Fixed preset palettes (e.g. `websafe216`) live inside it.
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
Spectrum's screen) for `npm run dither:zx`: Bayer 8 inside the cells as
a PNG and a `.scr` (the recommended mode, chosen by eye 2026-10-15 over
Bayer 4 and Atkinson), and Atkinson as a PNG, kept next to it for
comparison. Likewise at 320×200 (the C64's hires screen) for
`npm run dither:c64`: Bayer 8 as a PNG, a `.prg` and an `.art`, and
Atkinson as a PNG (chosen by eye 2026-10-18, as for the ZX; after
blurring, Bayer 8, Bayer 4 and Atkinson kept the tones equally well,
25.7/25.7/26.0, while Floyd–Steinberg and the Bayer 8 hybrid streaked,
about 35). Two steps, `--palette zx15 --kernel atkinson` and then
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
  outputs.
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
  risky work), CI, versions, releases — are in `CONTRIBUTING.md`; follow
  them. `npm run check` runs what CI (`.github/workflows/ci.yml`) runs:
  build with `--pedantic-packages --strict`, both test suites,
  `check:cli`. Keep the two in step.
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
