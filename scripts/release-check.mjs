// The release checks from CONTRIBUTING.md ("Releases"), for the library
// version about to be published. Run on your machine before tagging, and by
// CI on a version tag. Stops at the first failure, cheap checks first:
//
//   - the working tree is clean (spago publish requires it too)
//   - C: the version is `package.publish.version` in spago.yaml
//   - B: CHANGELOG.md has a section `## X.Y.Z - YYYY-MM-DD` with entries
//   - D: HEAD is on master as pushed to GitHub (origin/master)
//   - E: every library dependency has a version range
//   - F: the docs build (spago docs)
//   - A: npm run check (CI skips it: the same job has just run it)
//
// With --notes, checks only B and prints that section's text, the notes
// for the GitHub Release.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { parseArgs } from 'node:util';

const root = path.resolve(import.meta.dirname, '..');

const USAGE = `Usage: node scripts/release-check.mjs <X.Y.Z> [options]

  --skip-check  leave out A (npm run check), for CI
  --notes       print the version's CHANGELOG.md section and run no other check`;

function usage(message) {
  console.error(`${message}\n\n${USAGE}`);
  process.exit(1);
}

function pass(message) {
  console.error(`PASS  ${message}`);
}

function fail(message) {
  console.error(`FAIL  ${message}`);
  process.exit(1);
}

// Runs a command in the repository; returns its stdout, or null if it failed.
// The output is shown only with `show`, or when the command fails.
function run(command, args, { show = false } = {}) {
  try {
    return execFileSync(command, args, {
      cwd: root,
      encoding: 'utf8',
      stdio: show ? 'inherit' : 'pipe',
    }) ?? '';
  } catch (err) {
    if (!show) process.stderr.write(`${err.stdout ?? ''}${err.stderr ?? ''}`);
    return null;
  }
}

const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

// spago.yaml's `package.publish.version`. A regex, not a YAML parser (no
// dependency for one field): `version:` indented under `publish:`.
function publishVersion() {
  const match = read('spago.yaml').match(/^ {2}publish:\n(?: {4}.*\n)*? {4}version: *(\S+)/m);
  return match ? match[1] : null;
}

// The entries of the version's CHANGELOG.md section, up to the next `## `
// heading; null if there's no such section.
function changelogSection(version) {
  const lines = read('CHANGELOG.md').split('\n');
  const heading = new RegExp(`^## ${version.replaceAll('.', '\\.')} - \\d{4}-\\d{2}-\\d{2}$`);
  const start = lines.findIndex((line) => heading.test(line));
  if (start < 0) return null;
  const end = lines.findIndex((line, i) => i > start && line.startsWith('## '));
  return lines.slice(start + 1, end < 0 ? undefined : end).join('\n').trim();
}

// B. A section with at least one entry (a `- ` line).
function checkChangelog(version) {
  const section = changelogSection(version);
  if (section === null) {
    fail(`B: CHANGELOG.md has no heading "## ${version} - YYYY-MM-DD" ` +
      '(rename "## Unreleased" to it, and put a new, empty "## Unreleased" above)');
  }
  if (!/^- /m.test(section)) fail(`B: CHANGELOG.md's section for ${version} has no entries`);
  return section;
}

const { values: options, positionals } = (() => {
  try {
    return parseArgs({
      options: { 'skip-check': { type: 'boolean' }, notes: { type: 'boolean' } },
      allowPositionals: true,
    });
  } catch (err) {
    usage(err.message);
  }
})();
if (positionals.length !== 1) usage('Give the version to release, as X.Y.Z.');
const version = positionals[0];
if (!/^\d+\.\d+\.\d+$/.test(version)) usage(`Not a version X.Y.Z: ${version}`);

// The section with each wrapped paragraph or list entry joined into one
// line: GitHub shows every line break in a Release's notes.
function unwrap(text) {
  const continues = (line) => /^\s*[^\s#-]/.test(line);
  return text.split('\n').reduce((lines, line) => {
    const last = lines.length - 1;
    if (last >= 0 && lines[last] !== '' && continues(line) && !lines[last].startsWith('#')) {
      lines[last] += ` ${line.trim()}`;
    } else {
      lines.push(line);
    }
    return lines;
  }, []).join('\n');
}

if (options.notes) {
  console.log(unwrap(checkChangelog(version)));
  process.exit(0);
}

const status = run('git', ['status', '--porcelain']);
if (status === null) fail('could not run git status');
if (status !== '') fail(`the working tree isn't clean; commit or remove:\n${status}`);
pass('the working tree is clean');

const configured = publishVersion();
if (configured !== version) {
  fail(`C: spago.yaml's package.publish.version is ${configured ?? '(not found)'}, not ${version}`);
}
pass(`C: ${version} is the version in spago.yaml`);

checkChangelog(version);
pass(`B: CHANGELOG.md has a section for ${version}`);

if (run('git', ['fetch', '--quiet', 'origin', 'master']) === null) fail('D: could not fetch master from origin');
if (run('git', ['merge-base', '--is-ancestor', 'HEAD', 'FETCH_HEAD']) === null) {
  fail("D: HEAD isn't on master as pushed to GitHub (push master first)");
}
pass('D: HEAD is on origin/master');

// The tree was clean, so any change to spago.yaml comes from --ensure-ranges.
if (run('npx', ['spago', 'build', '-p', 'puregrain', '--ensure-ranges']) === null) fail('E: the build failed');
if (run('git', ['diff', '--quiet', '--', 'spago.yaml']) === null) {
  fail('E: spago build --ensure-ranges changed spago.yaml (missing ranges, or spago\'s own formatting); ' +
    'review git diff spago.yaml and commit it');
}
pass('E: every library dependency has a version range');

if (run('npx', ['spago', 'docs']) === null) fail('F: spago docs failed');
pass('F: the docs build');

if (options['skip-check']) {
  console.error('SKIP  A: npm run check (--skip-check)');
} else {
  if (run('npm', ['run', 'check'], { show: true }) === null) fail('A: npm run check failed');
  pass('A: npm run check');
}

console.error(`\nThe release checks pass for ${version}.` +
  (options['skip-check'] ? '' : ` Next: git tag v${version} (don't push it), then npx spago publish -p puregrain.`));
