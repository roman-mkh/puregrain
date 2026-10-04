# Contributing to puregrain

How work on puregrain is done: the setup, the branches, what CI checks,
versions, and releases. The design decisions behind the code, and why
they were made, are in [CLAUDE.md](CLAUDE.md); open work is in
[TODO.md](TODO.md).

## Setup

```bash
npm install       # the PureScript toolchain (purs, spago) and pngjs
npm run build     # the library and the CLI
npm run check     # everything CI checks (below)
```

`npm run check` runs, in order:

1. `spago build --pedantic-packages --strict`: the build, with every
   package dependency declared exactly, and compiler warnings treated as
   errors.
2. `spago test`: the library's tests, then the CLI's.
3. `npm run check:cli`: the end-to-end checks of the real CLI on
   generated images ([docs/test-images.md](docs/test-images.md#exact-checks)).

## Branches

- **Work happens on `master`.** Run `npm run check` before pushing; CI
  runs the same checks on every push, and `master` stays green.
- **Short-lived branches only for risky, multi-step work** (a large
  refactoring, say): push the branch, open a pull request, and merge once
  CI is green. No long-lived branches.
- **Releases are tags on `master`** (see below).

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs the three
checks of `npm run check` on every push to `master` and on every pull
request against it, each run as a clean build. Its result is the badge at
the top of the README. Keep the workflow and the `check` script in
`package.json` in step.

## Changes worth knowing

- **Tests:** new behaviour comes with tests: properties over arbitrary
  input where possible (QuickCheck), exact examples where they explain
  more.
- **Benchmarks:** performance claims come from a measurement, documented
  as a new dated section in
  [docs/benchmarks-dithering.md](docs/benchmarks-dithering.md), negative
  results included.
- **Public API:** start closed, open later. Exporting more later is
  compatible; removing an export breaks users. Public doc comments are
  shown on Pursuit, so they must make sense on their own there.

## Versions

[Semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`. Before
1.0, as is usual for PureScript packages, a breaking change raises the
minor version (0.1 → 0.2), and a compatible change or a fix the patch
version. The version lives in one place: `package.publish.version` in
`spago.yaml`.

From the first release on, `CHANGELOG.md` keeps an "Unreleased" section;
each change worth telling users adds a line to it.

## Releases

A release is a tag `vX.Y.Z` on `master`. Before it's published, these
must hold (to be automated in a `release.yml` workflow for tags):

- A. `npm run check` passes.
- B. `CHANGELOG.md` has a non-empty section for this version; it also
  becomes the GitHub Release's notes.
- C. The tag matches `package.publish.version` in `spago.yaml`.
- D. The tagged commit is on `master`.
- E. Every library dependency has a version range (`spago build
  --ensure-ranges` changes nothing).
- F. The docs build (`spago docs`), as Pursuit shows them.

Publishing goes through the PureScript registry with `spago publish`; the
registry then puts the docs on Pursuit. The first release is published by
hand, to see the process once; later ones from the workflow.
