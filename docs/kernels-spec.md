# Spec: eight more error-diffusion kernels

A working document (2026-11-04), the specification for adding eight
error-diffusion kernels to the library, the CLI and the web UI. It's
written so that anyone can implement it from here, a cloud session of
Claude Code included. After the merge it's deleted: its content lives on
in `docs/error-diffusion.md`, the CHANGELOG and the pull requests.

Read first: `CLAUDE.md` (the project's decisions and conventions) and
`CONTRIBUTING.md` (branches, checks, versions, releases).

## Decisions

- **Eight kernels:** Stucki, Burkes, the three Sierras, Fan, Shiau–Fan and
  Shiau–Fan 2 (tables below). Together with Floyd–Steinberg, Atkinson and
  Jarvis–Judice–Ninke, that makes 11.
- **No change to the dithering engine:** new presets in
  `Puregrain.Kernel`, written like `floydSteinberg`. The engine already
  takes any kernel (offsets pointing forward, any weights), and its
  mechanics are tested against an independent reference for random
  kernels (`Test.Puregrain.DiffusionMechanicsSpec`).
- **Everywhere:** the library, its facade `Puregrain` (choosing a kernel is
  the core decision in a dithering library), the CLI, and the web UI.
- **Release:** library **0.2.1**. New presets are a compatible addition,
  which raises the patch version before 1.0 (`CONTRIBUTING.md`,
  "Versions"). Releasing at once keeps the web UI's footer ("built on
  puregrain 0.2.1") true for the code it runs.
- **On a short-lived branch,** merged by pull request; in two phases:
  - **Phase A:** library, CLI, docs, release 0.2.1 (detailed below);
  - **Phase B:** the web UI's menu, designed and built in the branch
    (open points below), released as web UI v2.2.
- **Left out:**
  - *Simple 2D* (half the error right, half down): didactic only; it
    streaks, and Floyd–Steinberg is as cheap.
  - *Stevenson–Arce*: designed for pixels on a hexagonal grid ("for
    hexagonal cells", the libcaca study); on square pixels it's another
    filter than its authors tuned.
  - *False Floyd–Steinberg* (3/8, 3/8, 2/8): a speed shortcut of the
    time, "markedly worse" than the real one (Helland), and its name
    confuses. Sierra Lite is the better cheap kernel.

## Names

Family first, then the variant, so that a family sits together in
listings and menus. The Sierras by their numbered names, which are
established and say the number of rows: FFmpeg's `sierra3` and `sierra2`
(and `sierra2_4a`, its default), "Sierra-3" in Helland, `Sierra3` and
`Sierra2` in DitherPunk.jl. The light one by its usual name, "Sierra
Lite" (Helland; also "Filter Lite" on Wikipedia, and "Sierra-2-4A"). The
docs name every alias.

| Published names | Web UI label | CLI `--kernel` | Library |
|---|---|---|---|
| Stucki | Stucki | `stucki` | `stucki` |
| Burkes | Burkes | `burkes` | `burkes` |
| Sierra, three-row Sierra, Sierra-3 | Sierra 3 | `sierra-3` | `sierra3` |
| Two-row Sierra, Sierra-2 | Sierra 2 | `sierra-2` | `sierra2` |
| Sierra Lite, Filter Lite, Sierra-2-4A | Sierra Lite | `sierra-lite` | `sierraLite` |
| Fan | Fan | `fan` | `fan` |
| Shiau–Fan | Shiau-Fan | `shiau-fan` | `shiauFan` |
| Shiau–Fan 2 | Shiau-Fan 2 | `shiau-fan-2` | `shiauFan2` |

Labels and CLI names are strings in code, so they use the ASCII hyphen
(`CLAUDE.md`, "Dashes"), as "Floyd-Steinberg" does today.

## The kernels

Each table as published: `X` is the current pixel, the error goes right
of it and to the rows below, and the weights are divided by the divisor.
The offsets are what `Puregrain.Kernel`'s presets take: `dx` to the right,
`dy` down. Every table was checked against at least two independent
sources (see [Sources](#sources)); the weights of each add up to 1.

### Stucki (Peter Stucki, IBM Zurich, 1981), divisor 42, 12 neighbours over 2 rows

```
        X   8   4
2   4   8   4   2
1   2   4   2   1
```

Offsets (weight × 42): (1,0) 8, (2,0) 4; (−2,1) 2, (−1,1) 4, (0,1) 8,
(1,1) 4, (2,1) 2; (−2,2) 1, (−1,2) 2, (0,2) 4, (1,2) 2, (2,2) 1.
Good for: clean, sharp results, close to Jarvis–Judice–Ninke's, a little
faster (Wikipedia; Helland: "minimal difference" from JJN).
Sources: Helland, DitherPunk.jl; first published in Stucki's IBM report
RZ1060, 1981.

### Burkes (Daniel Burkes, 1988), divisor 32, 7 neighbours over 1 row

```
        X   8   4
2   4   8   4   2
```

Offsets (× 32): (1,0) 8, (2,0) 4; (−2,1) 2, (−1,1) 4, (0,1) 8, (1,1) 4,
(2,1) 2. Good for: a faster Stucki, its third row dropped, "with only a
minor hit to quality" (Helland). Sources: Helland, DitherPunk.jl
(its code; its docstring wrongly repeats Stucki's table).

### Sierra 3 (Frankie Sierra, 1989–1990), divisor 32, 10 neighbours over 2 rows

```
        X   5   3
2   4   5   4   2
    2   3   2
```

Offsets (× 32): (1,0) 5, (2,0) 3; (−2,1) 2, (−1,1) 4, (0,1) 5, (1,1) 4,
(2,1) 2; (−1,2) 2, (0,2) 3, (1,2) 2. Good for: results like Jarvis's,
faster (Wikipedia, the libcaca study). Sources: Helland, DitherPunk.jl.

### Sierra 2 (Frankie Sierra, 1989–1990), divisor 16, 7 neighbours over 1 row

```
        X   4   3
1   2   3   2   1
```

Offsets (× 16): (1,0) 4, (2,0) 3; (−2,1) 1, (−1,1) 2, (0,1) 3, (1,1) 2,
(2,1) 1. Good for: a faster Sierra 3 (Wikipedia). Sources: Helland,
DitherPunk.jl.

### Sierra Lite (Frankie Sierra, 1989–1990), divisor 4, 3 neighbours over 1 row

```
    X   2
1   1
```

Offsets (× 4): (1,0) 2; (−1,1) 1, (0,1) 1. Good for: much simpler and
faster than Floyd–Steinberg, with similar results (Wikipedia); "one of
the simplest Floyd–Steinberg derivatives" (the libcaca study). Sources:
Helland, DitherPunk.jl.

### Fan (Zhigang Fan, 1993), divisor 16, 4 neighbours over 1 row

```
        X   7
1   3   5
```

Offsets (× 16): (1,0) 7; (−2,1) 1, (−1,1) 3, (0,1) 5. Floyd–Steinberg
with one weight moved, its 1/16 from below-right to two columns left
(the libcaca study: it "just moves one coefficient around"); Shiau and
Fan's kernels below build on it. Sources:
DitherPunk.jl, ditherit.com's code; first published in Z. Fan, "A Simple
Modification of Error Diffusion Weights", IS&T's 46th Annual Conference,
1993.

### Shiau–Fan (Jeng-Nan Shiau and Zhigang Fan, 1993), divisor 8, 4 neighbours over 1 row

```
        X   4
1   1   2
```

Offsets (× 8): (1,0) 4; (−2,1) 1, (−1,1) 1, (0,1) 2. Good for: fewer
"worm" artifacts than Floyd–Steinberg, with weights that are powers of
two (their 1996 SPIE paper's title: "A set of easily implementable
coefficients in error diffusion with reduced worm artifacts"). Sources:
US patent 5,353,127, claim 2 (filed 1993-12-15, granted 1994-10-04,
Xerox); DitherPunk.jl; ditherit.com's code.

### Shiau–Fan 2 (Shiau and Fan, 1993), divisor 16, 5 neighbours over 1 row

```
            X   8
1   1   2   4
```

Offsets (× 16): (1,0) 8; (−3,1) 1, (−2,1) 1, (−1,1) 2, (0,1) 4. The same
aim, reaching one more column left. Sources: US patent 5,353,127, claim
4; DitherPunk.jl; ditherit.com's code.

## Phase A: library, CLI, docs, release 0.2.1

1. **Library** (`src/Puregrain/Kernel.purs`): the eight presets, each with
   a doc comment as for the existing three: what it is, its neighbours,
   what it's good for, and its source. Doc comments are shown on Pursuit,
   so they're self-contained and link with absolute URLs (`CLAUDE.md`,
   "Doc comments"). Exported from `Puregrain.Kernel`, and re-exported by
   the facade `src/Puregrain.purs`, whose doc comment lists the kernels.
2. **Tests** (`test/Test/Puregrain/KernelSpec.purs`): for each preset, its
   offsets and weights equal the table above, written out in the test
   independently of the library; every preset is accepted by
   `fromOffsets`, and its weights add up to 1. The engine's mechanics need
   no new tests.
3. **CLI:** the eight in `KernelName` and `kernelName`
   (`cli/src/Puregrain/Cli/Options.purs`); the help text and the tables
   derive from those. In `scripts/check-cli.sh`, the exact checks that
   hold for any kernel run with every kernel: check 2 (an image made of
   the palette's colors comes back unchanged) and check 6 (an image made
   of a machine's valid cells comes back unchanged). In `cli/README.md`,
   the kernels in the options.
4. **Docs:**
   - a new reference page, `docs/error-diffusion.md`, for all 11 kernels:
     how error diffusion works in a paragraph, each kernel's table, its
     aliases, its source with a link, and what it's good for, as the
     sources say it (our own impressions, if any, marked as such); how to
     define your own kernel with `fromOffsets`;
   - `README.md`: the feature line on error diffusion names the kernels
     briefly and links to the new page (the README summarizes and links);
     the page gets a row in the README's documentation table;
   - `CHANGELOG.md`: the 0.2.1 section;
   - `CLAUDE.md`: the `Puregrain.Kernel` entry names the presets.
5. **Release 0.2.1:** in the pull request, `package.publish.version` in
   `spago.yaml` set to 0.2.1 and the CHANGELOG's section dated; after the
   merge, the release as in `CONTRIBUTING.md`, "Releases"
   (`npm run release:check -- 0.2.1`, then `spago publish`).

Done when: `npm run check:clean` passes (CI likewise); `--kernel` takes
each new name; Pursuit's docs for `Puregrain.Kernel` and the facade list
all 11; 0.2.1 is in the registry.

## Phase B: the web UI (open points, to settle in the branch)

- The kernel menu grows from 4 entries to 12: its order and whether to
  group it (for example "Common" and "More"), designed and checked on a
  phone's width too.
- The labels from the table in [Names](#names), in `Text.purs`; the
  settings' kernel list and the worker's messages; the downloads' names,
  which use the CLI's names.
- Specs; one new kernel in `check:web` against the CLI.
- `web/README.md`: the table of settings as CLI options.
- Web UI v2.2: the footer, the README's status, the roadmap's versions.

## Sources

- Tanner Helland, ["Dithering: Eleven Algorithms and Source Code"](https://tannerhelland.com/2012/12/28/dithering-eleven-algorithms-source-code.html) (2012): the tables of Stucki, Burkes and the three Sierras; the names Sierra-3, Two-Row Sierra, Sierra Lite; False Floyd–Steinberg's verdict.
- [DitherPunk.jl's `error_diffusion.jl`](https://github.com/JuliaImages/DitherPunk.jl/blob/a8b3a623cc145fecb88c95212306cf0641710dd8/src/error_diffusion.jl): all eight tables as code, with references (Stucki 1981, Burkes 1988, Fan 1993, the Shiau–Fan patent and paper) and the aliases Sierra3, Sierra2, Sierra-2-4A.
- [US patent 5,353,127](https://patents.google.com/patent/US5353127A/en), Shiau and Fan: the weights of Shiau–Fan (claim 2) and Shiau–Fan 2 (claim 4).
- [The libcaca study, part 3](http://caca.zoy.org/study/part3.html) (Sam Hocevar): Fan "just moves one coefficient around"; Shiau–Fan's aim; Sierra as a faster Jarvis; Stevenson–Arce "for hexagonal cells".
- [Wikipedia, "Dither"](https://en.wikipedia.org/wiki/Dither): what each classic kernel is good for, in a sentence each.
- [FFmpeg's `paletteuse` filter](https://ffmpeg.org/ffmpeg-filters.html#paletteuse) (its options in [`vf_paletteuse.c`](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/vf_paletteuse.c)): the names `sierra3`, `sierra2` and `sierra2_4a`, the last its default.
- ditherit.com's code (its kernels as arrays in its script bundle, read 2026-11-03): Fan, Shiau–Fan and Shiau–Fan 2.
