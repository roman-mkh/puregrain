# Contributing to puregrain

How work on puregrain is done: the setup, the branches, what CI checks,
versions, the changelog, and releases. The design decisions behind the
code, and why they were made, are in [CLAUDE.md](CLAUDE.md); open work
is in [TODO.md](TODO.md).

## Setup

```bash
npm install       # the PureScript toolchain (purs, spago), pngjs and playwright-core
npm run build     # the library, the CLI, the examples and the web UI
npm run check     # everything CI checks (below)
```

The last check needs Docker, usable without sudo (for example, with the
user in the `docker` group). Only Docker is tested. The check calls the
`docker` command by name, so Podman would need one that runs it (the
`podman-docker` package); a shell alias doesn't reach the script.

`npm run check` runs, in order:

1. `spago build --pedantic-packages --strict`: the build, with every
   package dependency declared exactly, and compiler warnings treated as
   errors.
2. `spago test`: the tests of the library, the CLI and the web UI.
3. `npm run check:cli`: the end-to-end checks of the real CLI on
   generated images ([docs/test-images.md](docs/test-images.md#exact-checks)).
4. `npm run web:build`, then `npm run check:web`: the web UI bundled, and
   checked end to end in Chromium, Firefox and WebKit against the CLI's
   results and files ([web/README.md](web/README.md#development)). The
   browsers run in Playwright's Docker image, of the installed
   `playwright-core`'s version; the first run downloads it (about 1 GB,
   2.5 GB on disk), and each new version of Playwright a new one, so
   `docker image prune` now and then removes the old ones.

## Branches

- **Work happens on `master`.** Run `npm run check` before pushing; CI
  runs the same checks on every push, and `master` stays green.
- **Short-lived branches only for risky, multi-step work** (a large
  refactoring, say): push the branch, open a pull request, and merge once
  CI is green. No long-lived branches.
- **Releases are tags on `master`** (see below).

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs the four
checks of `npm run check` on every push to `master` and on every pull
request against it, each run as a clean build. Its result is the badge at
the top of the README. Keep the workflow and the `check` script in
`package.json` in step. On a version tag it also runs the release checks
and creates the GitHub Release (see [Releases](#releases)). On `master`,
once every check has passed, it publishes the web UI on GitHub Pages, at
https://roman-mkh.github.io/puregrain/: the bundle the browser checks
tested. For that, Pages must be on, with "GitHub Actions" as its source
(Settings → Pages).

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
- **Doc comments:** Pursuit shows them with the types, but without
  parameter names. So for each public function:
  1. a summary line;
  2. the arguments in signature order, one line each, named by their
     type, type variables included; a one-argument function whose
     summary already names the argument needs no list;
  3. the result, and how it fails (`Left`, `Nothing`, or a stop with an
     error);
  4. code examples: keep the existing ones, and add one where it helps.

  A type, record or class says what it stands for and lists its fields
  or methods. Rationale and implementation notes go in plain `--`
  comments or in `docs/`. [`Puregrain.Cells`](src/Puregrain/Cells.purs)
  shows the style.
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
5. `npx spago publish -p puregrain` (`-p` picks the library in our
   workspace). It checks a clean tree, C and E again, pushes the tag,
   builds with the versions its solver picks from the ranges, and sends
   the package to the registry.

**spago 1.0.4 reports a success as an error.** After sending the package
it may print "Registry did not like this and answered with status 201",
with a `jobId`. Status 201 means the registry *accepted* the job; spago
1.0.4 only counts 200 as success (fixed in spago's
[PR #1417](https://github.com/purescript/spago/pull/1417), not in a
release yet as of 2026-10-10). Don't publish again: check the job at
`https://registry.purescript.org/api/v1/jobs/<jobId>`, whose log shows
every step, and `"disposition": "published"` with `"success": true` once
it worked. The job that published 0.1.0, for example (as long as the
registry keeps it): <https://registry.purescript.org/api/v1/jobs/65ff05b2-b62c-477c-b1f6-282a92ff9c21>.

The docs are on Pursuit as soon as the job log says "Successfully uploaded
package docs to Pursuit", within a minute or two. Pursuit's search finds
the package only later, after its search index is rebuilt.

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
