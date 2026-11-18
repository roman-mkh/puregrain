# Spec: puregrain on npm, the command-line tool first

A working document (begun 2026-11-17, on the short-lived branch
`npm-package`): the plan for publishing the command-line tool as the npm
package `puregrain`, and for the third-party notices that its bundle and
puregrain lab's need. After the merge it's deleted, as the linear-light
spec was: what lasts moves to `CLAUDE.md`, `CONTRIBUTING.md` and the
READMEs.

## Decided (2026-11-17 and 18, with the user)

- **The package `puregrain`, the command `puregrain`,** and the CLI calls
  itself `puregrain` in everything it prints (open question 1, decided
  2026-11-18). The CLI first, to claim the name; the JavaScript API later, in the same package, as a step
  of its own (`TODO.md`, "npm package"). The command's name stays for good:
  renaming it later would break users' scripts.
- **The version is the library's,** from `package.publish.version` in the
  root `spago.yaml`, as the CLI's `--version` already is. **The first npm
  version is the next release's,** published together with its tag and
  the registry: 0.2.3, or 0.3.0 if the release holds a library change
  that alters output (the project's rule). Library features may join it;
  what goes in is decided before the release (2026-11-18). Revised from
  0.2.2: the CLI changed after the tag `v0.2.2` (`--version`, and its
  name, step a), so an npm 0.2.2 built from `master` would hold a CLI the
  tag doesn't, and the shared version would no longer identify the
  release.
- **pngjs is a dependency, `~7.0.0`** (patch versions only), not bundled:
  users get pngjs's fixes without a release of ours, `npm audit` sees it,
  and the bundle stays small; the risk of a broken or compromised patch is
  accepted, and the model can change later. The bundle leaves it out
  (esbuild's `external`).
- **A folder of its own, `npm/`,** like `web/` for the lab: the manifest,
  the npm page's README, the build script. The build writes the complete
  package into `npm/dist/` (gitignored), and the package is published from
  there: `npm publish npm/dist`.
- **The build copies the root `LICENSE` into `npm/dist/`:** npm doesn't
  take a parent folder's files.
- **`"exports"` allows only `./package.json`,** so nothing can be imported
  from the package yet, not even the CLI's bundle by its path. Adding the
  API's entry later then only adds; adding `"exports"` later, after users
  had imported a file, would break them. The `bin` command doesn't depend
  on `"exports"`.
- **From the first npm release, the CLI's options are a public contract:**
  renaming an option, or changing an exit code or an output, is a breaking
  change of the shared version (a minor step before 1.0, a major one
  after).
- **Third-party notices:** the bundles contain the compiled code of the
  PureScript packages they use, most under BSD-style licenses, whose terms
  ask that "redistributions in binary form must reproduce the above
  copyright notice". The npm package and puregrain lab's build both ship a
  `THIRD-PARTY-NOTICES.md`, made by one script.
- **The bundle is `spago bundle`'s, like the lab's,** minified except
  for names (2026-11-18; measurements under "The build").
- **`"author": "roman-mkh (https://github.com/roman-mkh)"`** (2026-11-18):
  a handle and the profile's link, as is common; the `LICENSE` keeps
  naming the copyright holder.
- **The npm page shows the logo,** pinned to the release's tag (below).
- **A short-lived branch,** merged with a merge commit once CI is green.
  The user publishes afterwards, from `master`, with the npm account's
  two-factor authentication.

## The package

`npm/dist/`, as published:

| File | What it is |
|---|---|
| `package.json` | The manifest (below), with the version from `spago.yaml` |
| `cli.mjs` | The bundle: `Puregrain.Cli.Main` with the library and its PureScript dependencies, starting with `#!/usr/bin/env node` |
| `README.md` | The npm page, from `npm/README.md` |
| `LICENSE` | The root's MIT license |
| `THIRD-PARTY-NOTICES.md` | The licenses of the PureScript packages in `cli.mjs` |

The manifest, `npm/package.json` (the build adds the version):

```json
{
  "name": "puregrain",
  "description": "Dithering for PNG images on the command line: error diffusion with 11 kernels, ordered (Bayer) dithering, retro palettes, a choice of gamma, and ZX Spectrum and C64 screens with their own file formats.",
  "license": "MIT",
  "author": "roman-mkh (https://github.com/roman-mkh)",
  "type": "module",
  "bin": { "puregrain": "cli.mjs" },
  "exports": { "./package.json": "./package.json" },
  "files": ["cli.mjs", "THIRD-PARTY-NOTICES.md"],
  "engines": { "node": ">=22" },
  "dependencies": { "pngjs": "~7.0.0" },
  "repository": { "type": "git", "url": "git+https://github.com/roman-mkh/puregrain.git", "directory": "npm" },
  "homepage": "https://github.com/roman-mkh/puregrain#readme",
  "bugs": "https://github.com/roman-mkh/puregrain/issues",
  "keywords": ["dithering", "floyd-steinberg", "atkinson", "bayer", "png", "zx-spectrum", "c64", "retro", "purescript", "cli"]
}
```

npm always includes `package.json`, `README.md` and `LICENSE`; `files`
names the rest.

## The build: `npm/build.mjs` (`npm run npm:build`)

1. Clears `dist/` first, as `web/build.mjs` clears `web/dist/`.
2. Bundles with `spago bundle -p puregrain-cli --module Puregrain.Cli.Main
   --platform node --bundle-type app`, as the lab's build bundles, with
   `--bundler-args "--external:pngjs --minify-whitespace --minify-syntax"`:
   pngjs left out, and the code minified except for its names, so stack
   traces in bug reports stay readable. (A correction: spago passes
   esbuild options through `--bundler-args`, or `extraArgs` in a
   package's `spago.yaml`; this spec first said it couldn't.) Then puts
   the `#!/usr/bin/env node` line first, since spago's own banner takes
   esbuild's banner option, and makes the file executable.
3. Writes `dist/package.json` from `npm/package.json` plus the version,
   copies `npm/README.md` with the release's tag filled into its links
   (the logo's included), copies the root `LICENSE`, and writes
   `THIRD-PARTY-NOTICES.md` with the notices script.

**Measured** (2026-11-18, esbuild with the same options, in a scratch
folder; all variants gave the launcher's PNGs, byte for byte):

| The CLI | Size | Compressed (gzip -9) | Startup (`--version`, median of 20) |
|---|---:|---:|---:|
| The launcher, today (about 190 separate files) | | | 199 ms |
| Bundled | 406 KB | 71 KB | 60 ms |
| Bundled, minified except names (chosen) | 273 KB | 60 KB | about the same |
| Bundled, fully minified | 189 KB | 45 KB | 58 ms |

Bundling is what makes it start faster; minifying only makes it
smaller. Bundling also shakes the tree: of the 192 PureScript modules
the CLI imports, 140 keep code in the bundle, and unused definitions
inside them go too. Full minifying renames everything, which a source
map would undo for stack traces, at more than the size it saves.
purs-backend-es, the optimizing backend (about 8% faster, measured
2026-10-10), stays out: the checks test the `purs` build, and a second
compiler in the release would need them all run on its output too.

## The notices script: `scripts/third-party-notices.mjs`

Shared by the npm build and the lab's (`web/build.mjs`):

- **Which packages:** it walks the compiled modules' imports from the
  entry modules (`import … from "../Data.Array/index.js"`), so it finds
  every module the bundle can contain, whatever the bundler. For the lab,
  from `Puregrain.Web.Main` and `Puregrain.Web.Worker`.
- **Module to package:** each module's source in `.spago/p/<name>-<version>/src/`
  names its package. The workspace's own modules (`Puregrain.*`) are ours,
  under the root `LICENSE`, and aren't listed.
- **The text:** each package's name, version, its license's SPDX name from
  its `purs.json`, and its license file in full. A package without one
  gets its SPDX name and a note saying so; the check makes sure the
  bundles' packages all have a file, or names those that don't.
- **Imports of npm packages** (`pngjs`, from `Png.js`) are listed apart:
  dependencies, not bundled, so no notice; the script fails on any it
  doesn't expect, so a new one can't slip into a bundle unnoticed.

The lab's build writes `web/dist/THIRD-PARTY-NOTICES.md`, served with the
page on GitHub Pages.

## The check: `npm run check:npm`

A script, `scripts/check-npm.mjs`:

- builds the package, packs it (`npm pack` in `npm/dist/`), and checks
  the tarball's files: exactly those of the table above;
- installs the tarball into an empty folder in the system's temporary
  directory (`npm install <tarball>`; pngjs comes from the npm registry, so
  it needs the network), and there:
  - `npx puregrain --version` prints `puregrain` and the version;
  - a few configurations give byte for byte the launcher's files: gray
    with a threshold, color with levels and a gamma, a palette, a ZX
    Spectrum `.scr` and a C64 `.prg`;
  - importing the package by a file's path fails
    (`ERR_PACKAGE_PATH_NOT_EXPORTED`);
- checks that the notices list every PureScript package in the bundle,
  each with a license text.

It joins `npm run check` and CI, after `check:cli`.

## Docs to update

- `npm/README.md`, new: the npm page, short, with absolute links (npm
  doesn't resolve the repository's relative ones): the logo, what it
  does, `npx puregrain …` and a few examples, Node 22 or later, the link
  to all the options in `cli/README.md`, to puregrain lab, and to the
  library on Pursuit. Its links to the repository's files name the
  release's tag (`…/puregrain/vX.Y.Z/logo/zx/lockup.svg`), filled in by
  the build, so a later change can't alter a published version's page;
  GitHub serves the logo's PNG and SVG with their right types
  (`raw.githubusercontent.com`, checked 2026-11-18). If npm drops the
  logo's `width`, it shows at its own 270 × 44.
- `cli/README.md`: installing from npm first (`npx puregrain`, `npm
  install -g puregrain`); running from a checkout stays, for development.
- `README.md`: "The command-line tool" says `npx puregrain`, not "isn't on
  npm yet".
- `CONTRIBUTING.md`: the release step for npm, after `spago publish`; the
  npm package's version is the library's; the changelog (open question 2).
- `CHANGELOG.md` or a changelog of the CLI's own (open question 2).
- `CLAUDE.md`: the npm package (folder, build, version, pngjs, `exports`,
  notices, check, publishing); the lab's notices.
- `TODO.md`: "npm package": the CLI's part done, the JavaScript API left.
- `web/README.md`: the lab's notices file.

## Steps

Each verified before the next, and stopping for review between them:

- **a. The CLI's name in its own output:** `puregrain` in the help, the
  usage line and `--version`, the name fixed instead of taken from the
  script's file name, which an npm `bin` link (or Windows' wrapper)
  would make `cli.mjs`; optparse's answers (help, version, rejections)
  end the process normally, with their exit code, so their text is
  written out in full even through a pipe.
- **b. The notices script,** used by the lab's build first: its
  `THIRD-PARTY-NOTICES.md` read through, and its packages compared with
  the bundles'.
- **c. The `npm/` folder:** the manifest, the README, the build; `.gitignore`
  gets `npm/dist/`; the root `package.json` gets `npm:build`.
- **d. The check,** `check:npm`, in `npm run check` and CI.
- **e. The docs** listed above.
- **f. The pull request,** CI green, merged with a merge commit.
- **Later, with the next release:** after `spago publish` (which pushes
  the tag the npm page's links name), the user publishes to npm from
  `master`: `npm login`, `npm run npm:build`, `npm pack --dry-run` in
  `npm/dist/` to see the files, `npm publish npm/dist`; and `npx
  puregrain@X.Y.Z --version` from an empty folder confirms it.

## Open questions

1. ~~The CLI's name in its own output~~: decided, `puregrain` (above).
2. **The CLI's changelog** (`CONTRIBUTING.md` promised one once it's
   published). Recommended: one `CHANGELOG.md` for the library and the
   CLI, since they share their versions, each version's section with the
   CLI's changes under a heading of their own (`### Command-line tool`);
   its first entry, the npm package's first version. The alternative,
   `cli/CHANGELOG.md`, would keep two files for one version.
3. ~~Minifying the bundle~~: decided, minified except for names (above).
4. **The lab's notices on the page.** Recommended: the file at the site's
   root, linked from `web/README.md`, but not from the footer, whose room
   on phones was just won back; a footer link can come with v3's page
   rework.
5. ~~The minimum Node version~~: decided, `>=22`, what CI and the
   development machine run; Node 20's support ended in April 2026.
6. ~~An `author` field~~: decided, the handle with the profile's link.
7. ~~The npm page's logo~~: decided, the ZX lockup, pinned to the tag.

## Before publishing (the user)

- An npm account with two-factor authentication (a passkey or a security
  key); `npm login` signs in through the browser.
- **The account's email is public:** npm writes it into every package's
  metadata (`npm view pngjs maintainers` shows its maintainer's address).
  GitHub's noreply address is unlikely to serve: npm sends a verification
  mail, and password resets and security notices, to the account's
  address, and the noreply address is an identifier for commits, not a
  mailbox (GitHub's docs don't say outright that mail to it is lost, but
  nothing suggests it's delivered). A forwarding alias of a real mailbox
  keeps the real address private and still receives npm's mail.
