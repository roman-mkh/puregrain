// Renders the scaling chart for docs/benchmarks-dithering.md from the JSON
// written by `node scripts/benchmark.mjs --json <file>`: median dithering
// time per quantizer mode against image side, log-log, with an O(N²)
// reference line. Writes a standalone SVG that follows the reader's light
// or dark color scheme.
//
//   node scripts/plot-benchmarks.mjs <results.json> <chart.svg> [build]
//
// For a run of several builds (benchmark --builds), [build] picks the one to
// plot; by default the first.
//
// Colors are the dataviz reference palette's first five categorical slots,
// in fixed order, validated for both modes (adjacent CVD ΔE >= 8, normal-
// vision ΔE >= 15). Three light-mode slots sit below 3:1 contrast, so the
// chart must stay next to its table in the doc (the "table view"); each
// series also gets its own marker shape. Text uses secondary ink: the
// palette's muted gray is only 3.5:1 on the light surface, too low for
// small text.

import fs from 'node:fs';

const [input, output, buildArg] = process.argv.slice(2);
if (!input || !output) {
  console.error('Usage: node scripts/plot-benchmarks.mjs <results.json> <chart.svg> [build]');
  process.exit(1);
}
const data = JSON.parse(fs.readFileSync(input, 'utf8'));
// Runs saved before --builds existed measured the purs build only.
const builds = data.builds ?? ['output'];
const build = buildArg ?? builds[0];
if (!builds.includes(build)) {
  console.error(`${input} has no build "${build}"; it has: ${builds.join(', ')}.`);
  process.exit(1);
}

// Series in the benchmark's fixed mode order; slot n = categorical slot n.
const SERIES = ['threshold', 'levels-gray', 'levels-rgb', 'websafe216', 'bw'];
const MARKERS = ['circle', 'square', 'diamond', 'triangle-up', 'triangle-down'];

const series = SERIES.map((mode, i) => {
  const points = data.results
    .filter((r) => (r.build ?? 'output') === build && r.kernel === 'floyd-steinberg' && r.mode === mode)
    .sort((a, b) => a.size - b.size);
  return { mode, slot: i + 1, marker: MARKERS[i], label: points[0]?.label ?? mode, points };
}).filter((s) => s.points.length > 0);
if (series.length === 0) {
  console.error(`${input} has no Floyd-Steinberg mode results to plot.`);
  process.exit(1);
}

// O(N²) reference through the default mode's largest measured size: the
// asymptotic regime. Points above it at small N are the fixed cold-start
// cost, which doesn't scale with the image.
const anchor = series[0].points[series[0].points.length - 1];
const sizes = data.sizes;
const reference = sizes.map((size) => ({ size, ms: anchor.median * (size / anchor.size) ** 2 }));

// ---- geometry ------------------------------------------------------------
const W = 760;
const H = 480;
const plot = { left: 78, right: W - 28, top: 118, bottom: H - 64 };

// The y axis ends at the data plus some headroom, not at the next whole
// decade (which can leave most of a decade empty); ticks stay at decades.
const allMs = [...series.flatMap((s) => s.points.map((p) => p.median)), ...reference.map((r) => r.ms)];
const yLo = Math.min(...allMs) / 1.6;
const yHi = Math.max(...allMs) * 1.6;
const xLo = Math.min(...sizes);
const xHi = Math.max(...sizes);
const pad = 0.35; // extra log2 units at both ends of the x axis, for the markers

const x = (size) => {
  const t = (Math.log2(size) - Math.log2(xLo) + pad) / (Math.log2(xHi) - Math.log2(xLo) + 2 * pad);
  return plot.left + t * (plot.right - plot.left);
};
const y = (msValue) => {
  const t = (Math.log10(msValue) - Math.log10(yLo)) / (Math.log10(yHi) - Math.log10(yLo));
  return plot.bottom - t * (plot.bottom - plot.top);
};
const f = (n) => n.toFixed(1);

const msLabel = (v) => (v >= 1000 ? `${v / 1000} s` : `${v} ms`);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function marker(shape, cx, cy, cls) {
  const r = 4.5;
  switch (shape) {
    case 'circle':
      return `<circle class="${cls}" cx="${f(cx)}" cy="${f(cy)}" r="${r}"/>`;
    case 'square':
      return `<rect class="${cls}" x="${f(cx - r)}" y="${f(cy - r)}" width="${2 * r}" height="${2 * r}" rx="1"/>`;
    case 'diamond': {
      const d = r * 1.3;
      return `<path class="${cls}" d="M${f(cx)} ${f(cy - d)}L${f(cx + d)} ${f(cy)}L${f(cx)} ${f(cy + d)}L${f(cx - d)} ${f(cy)}Z"/>`;
    }
    case 'triangle-up': {
      const d = r * 1.3;
      return `<path class="${cls}" d="M${f(cx)} ${f(cy - d)}L${f(cx + d)} ${f(cy + d * 0.8)}L${f(cx - d)} ${f(cy + d * 0.8)}Z"/>`;
    }
    default: {
      const d = r * 1.3;
      return `<path class="${cls}" d="M${f(cx)} ${f(cy + d)}L${f(cx + d)} ${f(cy - d * 0.8)}L${f(cx - d)} ${f(cy - d * 0.8)}Z"/>`;
    }
  }
}

// ---- pieces ----------------------------------------------------------------
const parts = [];

// Gridlines at each decade inside the axis, and at each measured size:
// hairline, solid.
for (let v = 10 ** Math.ceil(Math.log10(yLo)); v <= yHi; v *= 10) {
  parts.push(`<line class="grid" x1="${plot.left}" x2="${plot.right}" y1="${f(y(v))}" y2="${f(y(v))}"/>`);
  parts.push(`<text class="tick" x="${plot.left - 10}" y="${f(y(v) + 4)}" text-anchor="end">${msLabel(v)}</text>`);
}
for (const size of sizes) {
  parts.push(`<line class="grid" x1="${f(x(size))}" x2="${f(x(size))}" y1="${plot.top}" y2="${plot.bottom}"/>`);
  parts.push(`<text class="tick" x="${f(x(size))}" y="${plot.bottom + 20}" text-anchor="middle">${size}</text>`);
}
parts.push(`<line class="axis" x1="${plot.left}" x2="${plot.right}" y1="${plot.bottom}" y2="${plot.bottom}"/>`);
parts.push(`<line class="axis" x1="${plot.left}" x2="${plot.left}" y1="${plot.top}" y2="${plot.bottom}"/>`);

// Axis titles.
parts.push(`<text class="axis-title" x="${f((plot.left + plot.right) / 2)}" y="${H - 22}" text-anchor="middle">Image side N (px) - log scale</text>`);
parts.push(`<text class="axis-title" transform="translate(20 ${f((plot.top + plot.bottom) / 2)}) rotate(-90)" text-anchor="middle">Dithering time - log scale</text>`);

// O(N²) reference: dashed on purpose — it is a projection, not data.
const refPath = reference.map((r, i) => `${i === 0 ? 'M' : 'L'}${f(x(r.size))} ${f(y(r.ms))}`).join('');
parts.push(`<path class="reference" d="${refPath}"/>`);
const r0 = reference[0];
parts.push(`<text class="ref-label" x="${f(x(r0.size) + 8)}" y="${f(y(r0.ms) + 18)}">O(N²) reference</text>`);

// Series: 2px lines, then markers with a 2px surface ring on top.
for (const s of series) {
  const d = s.points.map((p, i) => `${i === 0 ? 'M' : 'L'}${f(x(p.size))} ${f(y(p.median))}`).join('');
  parts.push(`<path class="line s${s.slot}" d="${d}"><title>${esc(s.label)}</title></path>`);
}
for (const s of series) {
  for (const p of s.points) {
    parts.push(`<g><title>${esc(s.label)}, ${p.size}²: ${Math.round(p.median).toLocaleString('en-US')} ms</title>` +
      `${marker(s.marker, x(p.size), y(p.median), `mark s${s.slot}`)}</g>`);
  }
}

// Title, subtitle and legend (text in ink; identity from the key beside it).
const env = data.environment;
parts.push(`<text class="title" x="28" y="36">Dithering time vs. image size, by quantizer mode</text>`);
parts.push(`<text class="subtitle" x="28" y="58">Floyd-Steinberg · median of ${data.runs} runs · dithering only (no PNG I/O, no startup) · ${builds.length > 1 ? `build ${esc(build)} · ` : ''}${esc(env.date)}</text>`);
let lx = 28;
const ly = 88;
for (const s of series) {
  parts.push(`<line class="line s${s.slot}" x1="${lx}" x2="${lx + 22}" y1="${ly}" y2="${ly}"/>`);
  parts.push(marker(s.marker, lx + 11, ly, `mark s${s.slot}`));
  parts.push(`<text class="legend" x="${lx + 30}" y="${ly + 4}">${esc(s.label)}</text>`);
  lx += 30 + s.label.length * 7 + 22;
}
parts.push(`<line class="reference" x1="${lx}" x2="${lx + 22}" y1="${ly}" y2="${ly}"/>`);
parts.push(`<text class="legend" x="${lx + 30}" y="${ly + 4}">O(N²)</text>`);

const slots = {
  light: ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4'],
  dark: ['#3987e5', '#d95926', '#199e70', '#c98500', '#d55181'],
};
const vars = (mode) => slots[mode].map((c, i) => `--s${i + 1}: ${c};`).join(' ');

// The description states what this data shows, not what it should show:
// growth per doubling of the side over the three largest sizes — the same
// statistic scripts/benchmark.mjs reports, robust to one noisy median.
const upper = sizes.slice(-3);
const growths = series.filter((s) => s.points.length >= upper.length && upper.length >= 2).map((s) => {
  const first = s.points.find((p) => p.size === upper[0]).median;
  const last = s.points.find((p) => p.size === upper[upper.length - 1]).median;
  return (last / first) ** (1 / (upper.length - 1));
});
const desc = `Log-log line chart of median dithering time for ${series.length} quantizer modes. ` +
  (growths.length > 0
    ? `From ${upper[0]}² to ${upper[upper.length - 1]}² the times grow ×${Math.min(...growths).toFixed(2)} to ` +
      `×${Math.max(...growths).toFixed(2)} per doubling of the side (×4 is proportional to the pixel count, ` +
      `the dashed O(N²) reference). `
    : '') +
  `Exact values are in the table next to this chart.`;

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}" role="img" aria-labelledby="t d">
<title id="t">Dithering time vs. image size, by quantizer mode</title>
<desc id="d">${esc(desc)}</desc>
<style>
  svg {
    --surface: #fcfcfb; --ink: #0b0b0b; --ink-2: #52514e; --muted: #898781;
    --grid: #e1e0d9; --axis: #c3c2b7; ${vars('light')}
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  }
  @media (prefers-color-scheme: dark) {
    svg {
      --surface: #1a1a19; --ink: #ffffff; --ink-2: #c3c2b7; --muted: #898781;
      --grid: #2c2c2a; --axis: #383835; ${vars('dark')}
    }
  }
  .bg { fill: var(--surface); }
  .grid { stroke: var(--grid); stroke-width: 1; }
  .axis { stroke: var(--axis); stroke-width: 1; }
  .tick { fill: var(--ink-2); font-size: 11px; font-variant-numeric: tabular-nums; }
  .axis-title, .legend, .ref-label { fill: var(--ink-2); font-size: 12px; }
  .title { fill: var(--ink); font-size: 16px; font-weight: 600; }
  .subtitle { fill: var(--ink-2); font-size: 12px; }
  .reference { fill: none; stroke: var(--muted); stroke-width: 1.5; stroke-dasharray: 5 4; }
  .line { fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }
  .mark { stroke: var(--surface); stroke-width: 2; }
  ${[1, 2, 3, 4, 5].map((n) => `.line.s${n} { stroke: var(--s${n}); } .mark.s${n} { fill: var(--s${n}); }`).join('\n  ')}
</style>
<rect class="bg" width="${W}" height="${H}" rx="8"/>
${parts.join('\n')}
</svg>
`;

fs.writeFileSync(output, svg);
console.log(`Wrote ${output}`);
