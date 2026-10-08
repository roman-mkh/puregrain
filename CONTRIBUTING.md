# Contributing to puregrain

How work on puregrain is done: the setup, the branches, what CI checks,
versions, the changelog, and releases. The design decisions behind the
code, and why they were made, are in [CLAUDE.md](CLAUDE.md); open work
is in [TODO.md](TODO.md).

## Setup

```bash
npm install       # the PureScript toolchain (purs, spago) and pngjs
npm run build     # the library, the CLI and the examples
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
`package.json` in step. On a version tag it also runs the release checks
and creates the GitHub Release (see [Releases](#releases)).

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
- **Examples:** the README's "Getting started" shows an excerpt of
  [`QuickStart.purs`](examples/src/Puregrain/Examples/QuickStart.purs),
  copied by hand. When that file changes, refresh the excerpt. The build
  compiles the examples, so an API change that breaks them fails CI.
- **Dashes:** code (string literals, test names, messages, config values)
  uses only the hyphen `-`: in ranges (`0-255`), in name pairs
  (`Floyd-Steinberg`), and ` - ` where a sentence would take a dash.
  Comments and `.md` files may keep typographic dashes (`–`, `—`).

## Versions

[Semantic versioning](https://semver.org): `MAJOR.MINOR.PATCH`. Before
1.0, as is usual for PureScript packages, a breaking change raises the
minor version (0.1 → 0.2), and a compatible change or a fix the patch
version. The version lives in one place: `package.publish.version` in
`spago.yaml`.

## Changelog

`CHANGELOG.md` covers the library, in the "Keep a Changelog" style: the
newest version first, its entries grouped under Added, Changed, Removed
and Fixed. Each change worth telling users adds a line to the
`## Unreleased` section at the top. At a release, that heading becomes
`## X.Y.Z - YYYY-MM-DD` (the tag's version and date), and a new, empty
`## Unreleased` goes above it. Headings stay plain, without links, so
the release checks can find a version's section.

The CLI isn't published yet; when it is, it gets its own changelog.

## Releases

A release is a tag `vX.Y.Z` on `master`. Before it's published, these
must hold:

- A. `npm run check` passes.
- B. `CHANGELOG.md` has a non-empty section for this version (the
  "Unreleased" section renamed; see [Changelog](#changelog)); it also
  becomes the GitHub Release's notes.
- C. The tag matches `package.publish.version` in `spago.yaml`.
- D. The tagged commit is on `master` as pushed to GitHub.
- E. Every library dependency has a version range (`spago build
  --ensure-ranges` changes nothing).
- F. The docs build (`spago docs`), as Pursuit shows them.

`npm run release:check -- X.Y.Z` (`scripts/release-check.mjs`) checks
them all, first that the working tree is clean.

Publishing goes through the PureScript registry with `spago publish`; the
registry then puts the docs on Pursuit. No account is needed. The steps:

1. In `CHANGELOG.md`, rename `## Unreleased` to `## X.Y.Z - YYYY-MM-DD`
   and put a new, empty `## Unreleased` above it. Set
   `package.publish.version` in `spago.yaml` to `X.Y.Z` if it isn't yet.
   Commit ("Release X.Y.Z"): this is the commit that gets published.
2. Push `master` and wait until CI is green.
3. `npm run release:check -- X.Y.Z`
4. `git tag vX.Y.Z`, and **don't push the tag**: `spago publish` does
   that itself, right before it calls the registry. A tag pushed earlier
   points at an unpublished commit if the registry then rejects it.
5. `spago publish -p puregrain` (`-p` picks the library in our
   workspace). It checks a clean tree, C and E again, pushes the tag,
   builds with the versions its solver picks from the ranges, and sends
   the package to the registry.

The tag push starts CI: it runs the checks again and creates the GitHub
Release from the changelog section. It can't stop the publish, which is
why the checks run locally first (step 3).

**After the first release, a pushed version tag publishes itself.** Once
a day (07:00 UTC), the registry publishes every new version tag of its
packages on GitHub, with or without `spago publish`, if the tag points to
a commit from the last 24 hours. So push a version tag only when the
release is meant to happen. A wrong tag pushed by mistake must be deleted
before the next run.

If something fails before the tag is pushed, delete it (`git tag -d
vX.Y.Z`), fix the problem in a new commit, and tag again. If the registry
rejects the package after the tag was pushed, also delete the tag on
GitHub (`git push origin --delete vX.Y.Z`), and the GitHub Release if CI
created one.

The first releases are published by hand, as above. Publishing from CI
would need the workflow to create the tag itself (a manual "Run
workflow" button), a later step.
