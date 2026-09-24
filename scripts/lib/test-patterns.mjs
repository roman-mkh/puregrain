// Drawing primitives, test-image tiles, and composite layouts for the
// generated test images. What each tile is for, and what to look for in
// its dithered output, is documented in docs/test-images.md — keyed by
// the same tile ids used here.
//
// Everything draws into a pngjs `PNG` (an RGBA byte buffer) and is fully
// deterministic: no randomness, so every run on every machine produces
// byte-identical images, which reproducible benchmarks depend on.
//
// Tiles draw into a rect they're given, with all geometry proportional to
// that rect — so the same tile works rendered alone (full frame) or as one
// region of a composite, at any image size.

import { PNG } from 'pngjs';

// ---------------------------------------------------------------------------
// Primitives

export const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
export const lerp = (a, b, t) => a + (b - a) * t;
export const lerpRGB = (c1, c2, t) => [lerp(c1[0], c2[0], t), lerp(c1[1], c2[1], t), lerp(c1[2], c2[2], t)];
export const gray = (v) => [v, v, v];

// Every channel write is rounded and clamped to [0,255] here, once:
// png.data is a byte buffer, and a raw assignment would truncate
// fractions and wrap out-of-range values modulo 256 (256 -> 0, -1 -> 255).
const toByte = (v) => clamp(Math.round(v), 0, 255);

export function setRGB(img, x, y, rgb) {
  const idx = (y * img.width + x) * 4;
  img.data[idx] = toByte(rgb[0]);
  img.data[idx + 1] = toByte(rgb[1]);
  img.data[idx + 2] = toByte(rgb[2]);
  img.data[idx + 3] = 255;
}

export function getRGB(img, x, y) {
  const idx = (y * img.width + x) * 4;
  return [img.data[idx], img.data[idx + 1], img.data[idx + 2]];
}

// Calls fn(x, y, u, v) for every pixel of rect. u and v run from 0 at the
// rect's first column/row to exactly 1 at its last, so a ramp drawn with
// them hits both of its end values exactly.
export function forEachPixel(rect, fn) {
  const { x0, y0, w, h } = rect;
  for (let y = y0; y < y0 + h; y++) {
    const v = h > 1 ? (y - y0) / (h - 1) : 0;
    for (let x = x0; x < x0 + w; x++) {
      const u = w > 1 ? (x - x0) / (w - 1) : 0;
      fn(x, y, u, v);
    }
  }
}

export function fillRect(img, rect, rgb) {
  forEachPixel(rect, (x, y) => setRGB(img, x, y, rgb));
}

// The part of `rect` between fractional bounds, snapped to whole pixels.
// Neighbouring sub-rects built from the same fractions share their edges
// exactly: no gaps, no overlaps.
export function subRect(rect, fx0, fy0, fx1, fy1) {
  const x0 = rect.x0 + Math.round(fx0 * rect.w);
  const y0 = rect.y0 + Math.round(fy0 * rect.h);
  const x1 = rect.x0 + Math.round(fx1 * rect.w);
  const y1 = rect.y0 + Math.round(fy1 * rect.h);
  return { x0, y0, w: x1 - x0, h: y1 - y0 };
}

export function createImage(width, height, fill = gray(128)) {
  const img = new PNG({ width, height });
  // pngjs zero-fills the buffer — fully transparent. Written without an
  // alpha channel, a transparent pixel is blended over pngjs's default
  // WHITE background, so any pixel no tile paints would silently turn
  // white. Paint the whole canvas opaque first.
  fillRect(img, { x0: 0, y0: 0, w: width, h: height }, fill);
  return img;
}

// Anti-aliased line segment from a to b ([x, y], pixel centers at +0.5),
// `width` px wide with round caps, clipped to `clip`. Coverage falls off
// linearly over one pixel at the edge and is blended over what's there.
export function drawSegment(img, clip, a, b, width, rgb) {
  const [ax, ay] = a;
  const [bx, by] = b;
  const reach = width / 2 + 0.5;
  const xMin = Math.max(clip.x0, Math.floor(Math.min(ax, bx) - reach));
  const xMax = Math.min(clip.x0 + clip.w - 1, Math.ceil(Math.max(ax, bx) + reach));
  const yMin = Math.max(clip.y0, Math.floor(Math.min(ay, by) - reach));
  const yMax = Math.min(clip.y0 + clip.h - 1, Math.ceil(Math.max(ay, by) + reach));
  const dx = bx - ax;
  const dy = by - ay;
  const len2 = dx * dx + dy * dy;
  for (let y = yMin; y <= yMax; y++) {
    for (let x = xMin; x <= xMax; x++) {
      const px = x + 0.5;
      const py = y + 0.5;
      const t = len2 > 0 ? clamp(((px - ax) * dx + (py - ay) * dy) / len2, 0, 1) : 0;
      const dist = Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
      const coverage = clamp(width / 2 + 0.5 - dist, 0, 1);
      if (coverage > 0) setRGB(img, x, y, lerpRGB(getRGB(img, x, y), rgb, coverage));
    }
  }
}

// HSL -> RGB: h in degrees (wraps at 360), s and l in [0,1]; channels in [0,255].
export function hslToRgb(h, s, l) {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  const [r1, g1, b1] =
    hp < 1 ? [c, x, 0] :
    hp < 2 ? [x, c, 0] :
    hp < 3 ? [0, c, x] :
    hp < 4 ? [0, x, c] :
    hp < 5 ? [x, 0, c] :
             [c, 0, x];
  const m = l - c / 2;
  return [(r1 + m) * 255, (g1 + m) * 255, (b1 + m) * 255];
}

// Color at t in [0,1] along evenly spaced color stops, interpolated linearly.
function gradientAt(stops, t) {
  const pos = clamp(t, 0, 1) * (stops.length - 1);
  const i = Math.min(Math.floor(pos), stops.length - 2);
  return lerpRGB(stops[i], stops[i + 1], pos - i);
}

const normalize = ([x, y, z]) => {
  const n = Math.hypot(x, y, z);
  return [x / n, y / n, z / n];
};

// A sphere lit from the upper left (Lambert diffuse + Blinn-Phong
// specular highlight), anti-aliased at the rim, centered in `rect`.
function drawSphere(img, rect, base, background) {
  const cx = rect.x0 + rect.w / 2;
  const cy = rect.y0 + rect.h / 2;
  const radius = 0.42 * Math.min(rect.w, rect.h);
  const light = normalize([-0.45, -0.55, 0.7]); // y grows downward: -y is "up"
  const half = normalize([light[0], light[1], light[2] + 1]); // viewer looks along -z
  forEachPixel(rect, (x, y) => {
    const px = x + 0.5 - cx;
    const py = y + 0.5 - cy;
    const coverage = clamp(radius - Math.hypot(px, py) + 0.5, 0, 1);
    if (coverage === 0) {
      setRGB(img, x, y, background);
      return;
    }
    const nx = px / radius;
    const ny = py / radius;
    const nz = Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny));
    const diffuse = Math.max(0, nx * light[0] + ny * light[1] + nz * light[2]);
    const specular = Math.pow(Math.max(0, nx * half[0] + ny * half[1] + nz * half[2]), 40);
    const shade = 0.12 + 0.88 * diffuse;
    const lit = base.map((c) => c * shade + 255 * 0.8 * specular);
    setRGB(img, x, y, lerpRGB(background, lit, coverage));
  });
}

// Flat patches, filled row by row in a cols x rows grid.
function drawPatchGrid(img, rect, colors, cols, rows) {
  colors.forEach((rgb, i) => {
    const col = i % cols;
    const row = Math.floor(i / cols);
    fillRect(img, subRect(rect, col / cols, row / rows, (col + 1) / cols, (row + 1) / rows), rgb);
  });
}

// ---------------------------------------------------------------------------
// Tile data

// Step-wedge levels: dense near black and white, where error diffusion
// looks worst (sparse dots, late onset, "worms"), plus the two levels
// straddling the 50% point. The light row is the dark row mirrored
// (v -> 255 - v), so the two rows should look roughly like negatives.
const WEDGE_DARK = [0, 1, 2, 4, 8, 16, 32, 64, 96, 126, 127];
const WEDGE_LIGHT = WEDGE_DARK.map((v) => 255 - v).reverse();

// 1, 2 and 3 px wide lines (rows) at five angles (columns).
const LINE_WIDTHS = [1, 2, 3];
const LINE_ANGLES = [0, 22.5, 45, 67.5, 90];

// Exact web-safe colors: every channel is one of 0, 51, 102, 153, 204, 255.
const PALETTE_EXACT = [
  [0, 0, 0], [255, 255, 255], [102, 102, 102], [153, 153, 153],
  [255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0],
  [0, 255, 255], [255, 0, 255], [51, 102, 153], [204, 153, 102],
];

// Colors halfway between neighbouring web-safe steps in one or more
// channels. The exact midpoints (25.5, 76.5, 127.5, ...) aren't
// representable in 8 bits, so each is rounded up by 0.5 (26, 77, 128, ...).
const PALETTE_MIDPOINTS = [
  [26, 26, 26], [77, 77, 77], [128, 128, 128], [230, 230, 230],
  [128, 0, 0], [0, 128, 0], [0, 0, 128], [128, 128, 0],
  [0, 128, 128], [128, 0, 128], [26, 128, 230], [230, 128, 26],
];

// A hand-picked light-to-dark range of skin tones (not a standard scale).
const SKIN_TONES = [
  [250, 222, 200], [236, 188, 150], [214, 156, 112],
  [176, 116, 76], [125, 78, 50], [72, 45, 30],
];

// Channel ramps, top to bottom. Gray comes first on purpose: rendered
// alone, the gray stripe then starts at the top of the image with zero
// error in every channel, so scalarED must keep it exactly neutral.
const CHANNEL_STRIPES = [(t) => [t, t, t], (t) => [t, 0, 0], (t) => [0, t, 0], (t) => [0, 0, t]];

// ---------------------------------------------------------------------------
// Tile registry. Ids are "<pattern>:<name>"; the pattern decides the PNG
// type a tile is written as when rendered alone (see COMPOSITES).

export const TILES = [
  // --- gray ---------------------------------------------------------------
  {
    id: 'gray:ramp',
    description: 'Horizontal ramp 0→255: tone reproduction over the whole range.',
    draw: (img, rect) => forEachPixel(rect, (x, y, u) => setRGB(img, x, y, gray(255 * u))),
  },
  {
    id: 'gray:wedges',
    description: 'Flat step wedges at exact levels, dense near black and white; light row mirrors dark row.',
    draw: (img, rect) =>
      [WEDGE_DARK, WEDGE_LIGHT].forEach((levels, row) =>
        levels.forEach((level, i) =>
          fillRect(img, subRect(rect, i / levels.length, row / 2, (i + 1) / levels.length, (row + 1) / 2), gray(level)),
        ),
      ),
  },
  {
    id: 'gray:vramp',
    description: 'Vertical ramp 0→255: same tones as gray:ramp, along the other axis (direction-dependent artifacts).',
    draw: (img, rect) => forEachPixel(rect, (x, y, u, v) => setRGB(img, x, y, gray(255 * v))),
  },
  {
    id: 'gray:sphere',
    description: 'Shaded sphere with a specular highlight: smooth 2D shading, highlight roll-off to white.',
    draw: (img, rect) => drawSphere(img, rect, gray(235), gray(64)),
  },
  {
    id: 'gray:zone-plate',
    description: 'Zone plate: rings rising from zero frequency at the center to the Nyquist limit at the rim (moiré).',
    draw: (img, rect) => {
      const cx = rect.x0 + rect.w / 2;
      const cy = rect.y0 + rect.h / 2;
      const rmax = Math.min(rect.w, rect.h) / 2;
      // Phase k*r^2 has local frequency k*r/pi cycles/px: 0.5 (Nyquist) at r = rmax.
      const k = Math.PI / (2 * rmax);
      forEachPixel(rect, (x, y) => {
        const r = Math.hypot(x + 0.5 - cx, y + 0.5 - cy);
        setRGB(img, x, y, gray(r <= rmax ? 127.5 + 127.5 * Math.cos(k * r * r) : 127.5));
      });
    },
  },
  {
    id: 'gray:shadows-highlights',
    description: 'The extremes magnified: ramp 0→32 (top half) and 223→255 (bottom half) — dot onset, worms.',
    draw: (img, rect) => {
      forEachPixel(subRect(rect, 0, 0, 1, 0.5), (x, y, u) => setRGB(img, x, y, gray(32 * u)));
      forEachPixel(subRect(rect, 0, 0.5, 1, 1), (x, y, u) => setRGB(img, x, y, gray(223 + 32 * u)));
    },
  },
  {
    id: 'gray:lines',
    description: 'Dark anti-aliased lines, 1/2/3 px wide (rows) at 0–90° (columns), on light gray: thin detail.',
    draw: (img, rect) => {
      fillRect(img, rect, gray(224));
      LINE_WIDTHS.forEach((width, row) =>
        LINE_ANGLES.forEach((deg, col) => {
          const cell = subRect(rect, col / LINE_ANGLES.length, row / LINE_WIDTHS.length,
            (col + 1) / LINE_ANGLES.length, (row + 1) / LINE_WIDTHS.length);
          const half = 0.4 * Math.min(cell.w, cell.h);
          // Snap the center so axis-aligned lines come out crisp: odd widths
          // on a pixel center, even widths on a pixel edge.
          const snap = (c) => (width % 2 === 1 ? Math.floor(c) + 0.5 : Math.round(c));
          const cx = snap(cell.x0 + cell.w / 2);
          const cy = snap(cell.y0 + cell.h / 2);
          const t = (deg * Math.PI) / 180;
          const dx = Math.cos(t) * half;
          const dy = -Math.sin(t) * half; // y grows downward: positive angles tilt up
          drawSegment(img, cell, [cx - dx, cy - dy], [cx + dx, cy + dy], width, gray(32));
        }),
      );
    },
  },
  {
    id: 'gray:edges',
    description: 'Solid black and white blocks on mid-gray, crossed by a mid-gray diagonal: hard edges, bleed.',
    draw: (img, rect) => {
      fillRect(img, rect, gray(128));
      fillRect(img, subRect(rect, 0.1, 0.15, 0.45, 0.85), gray(0));
      fillRect(img, subRect(rect, 0.55, 0.15, 0.9, 0.85), gray(255));
      const p = (fx, fy) => [rect.x0 + fx * rect.w, rect.y0 + fy * rect.h];
      drawSegment(img, rect, p(0.05, 0.05), p(0.95, 0.95), 2, gray(128));
    },
  },

  // --- color --------------------------------------------------------------
  {
    id: 'color:hue-lightness',
    description: 'Every hue (across) at every lightness, white → pure → black (down): the gamut surface.',
    draw: (img, rect) => forEachPixel(rect, (x, y, u, v) => setRGB(img, x, y, hslToRgb(360 * u, 1, 1 - v))),
  },
  {
    id: 'color:hue-saturation',
    description: 'Every hue (across) fading from vivid to neutral gray (down): colored noise in near-grays.',
    draw: (img, rect) => forEachPixel(rect, (x, y, u, v) => setRGB(img, x, y, hslToRgb(360 * u, 1 - v, 0.5))),
  },
  {
    id: 'color:channel-ramps',
    description: 'Ramps 0→255 in gray, R, G, B stripes (top to bottom): each channel on its own (scalarED).',
    draw: (img, rect) =>
      CHANNEL_STRIPES.forEach((color, i) =>
        forEachPixel(subRect(rect, 0, i / CHANNEL_STRIPES.length, 1, (i + 1) / CHANNEL_STRIPES.length),
          (x, y, u) => setRGB(img, x, y, color(255 * u))),
      ),
  },
  {
    id: 'color:pastels-skin',
    description: 'Pastel hue sweep (top) and a light → dark skin-tone gradient (bottom): subtle, low-saturation.',
    draw: (img, rect) => {
      forEachPixel(subRect(rect, 0, 0, 1, 0.5), (x, y, u) => setRGB(img, x, y, hslToRgb(360 * u, 0.55, 0.82)));
      forEachPixel(subRect(rect, 0, 0.5, 1, 1), (x, y, u) => setRGB(img, x, y, gradientAt(SKIN_TONES, u)));
    },
  },
  {
    id: 'color:palette-exact',
    description: 'Flat patches of exact web-safe colors: must come out noise-free (zero error) under web-safe.',
    draw: (img, rect) => drawPatchGrid(img, rect, PALETTE_EXACT, 4, 3),
  },
  {
    id: 'color:palette-midpoints',
    description: 'Flat patches halfway between web-safe steps: the ~50/50 mix pattern of two palette colors.',
    draw: (img, rect) => drawPatchGrid(img, rect, PALETTE_MIDPOINTS, 4, 3),
  },
  {
    id: 'color:sphere',
    description: 'Colored sphere with a white specular highlight on a dark bluish-gray: smooth color shading.',
    draw: (img, rect) => drawSphere(img, rect, [220, 70, 50], [60, 64, 72]),
  },
];

// ---------------------------------------------------------------------------
// Composites: which tiles go where, as fractions [x0, y0, x1, y1] of the
// image. Ramps and wedges are full-width bands (tonal resolution comes from
// length); everything else is a tile in a grid below them.

export const COMPOSITES = {
  gray: {
    colorType: 0, // 8-bit grayscale PNG
    description: 'grayscale composite — two full-width tone bands over a 3×2 grid of tiles',
    layout: [
      ['gray:ramp', 0, 0, 1, 1 / 8],
      ['gray:wedges', 0, 1 / 8, 1, 1 / 4],
      ['gray:vramp', 0, 1 / 4, 1 / 3, 5 / 8],
      ['gray:sphere', 1 / 3, 1 / 4, 2 / 3, 5 / 8],
      ['gray:zone-plate', 2 / 3, 1 / 4, 1, 5 / 8],
      ['gray:shadows-highlights', 0, 5 / 8, 1 / 3, 1],
      ['gray:lines', 1 / 3, 5 / 8, 2 / 3, 1],
      ['gray:edges', 2 / 3, 5 / 8, 1, 1],
    ],
  },
  color: {
    colorType: 2, // 8-bit RGB PNG (no alpha)
    description: 'truecolor composite — four full-width bands over a row of 3 tiles',
    // The sphere sits between the two patch grids on purpose: side by side
    // they'd read as one grid, hiding where exact colors (expected noise-
    // free) end and midpoints (expected ~50/50 mix) begin.
    layout: [
      ['color:hue-lightness', 0, 0, 1, 3 / 16],
      ['color:hue-saturation', 0, 3 / 16, 1, 5 / 16],
      ['color:channel-ramps', 0, 5 / 16, 1, 8 / 16],
      ['color:pastels-skin', 0, 8 / 16, 1, 10 / 16],
      ['color:palette-exact', 0, 10 / 16, 1 / 3, 1],
      ['color:sphere', 1 / 3, 10 / 16, 2 / 3, 1],
      ['color:palette-midpoints', 2 / 3, 10 / 16, 1, 1],
    ],
  },
};

export function findTile(id) {
  return TILES.find((t) => t.id === id);
}

// The composite a tile belongs to — the part of its id before the colon.
export const patternOf = (tileId) => tileId.split(':')[0];

// Fail fast if the registry and the layouts ever drift apart.
for (const [name, composite] of Object.entries(COMPOSITES)) {
  for (const [id] of composite.layout) {
    if (!findTile(id)) throw new Error(`Composite "${name}" places unknown tile "${id}"`);
    if (patternOf(id) !== name) throw new Error(`Tile "${id}" placed in the wrong composite "${name}"`);
  }
}
for (const tile of TILES) {
  if (!COMPOSITES[patternOf(tile.id)]) throw new Error(`Tile "${tile.id}" belongs to no composite`);
}

const fullFrame = (width, height) => ({ x0: 0, y0: 0, w: width, h: height });

export function renderComposite(name, width, height) {
  const img = createImage(width, height);
  for (const [id, fx0, fy0, fx1, fy1] of COMPOSITES[name].layout) {
    findTile(id).draw(img, subRect(fullFrame(width, height), fx0, fy0, fx1, fy1));
  }
  return img;
}

export function renderTile(id, width, height) {
  const img = createImage(width, height);
  findTile(id).draw(img, fullFrame(width, height));
  return img;
}
