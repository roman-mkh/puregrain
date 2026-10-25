// The loops over a whole picture for Puregrain.Web.Prepare: RGBA bytes,
// row after row, in a Uint8ClampedArray. Specs pin them to the module's
// rules.

export const hasTransparency = (pixels) => () => {
  for (let i = 3; i < pixels.length; i += 4) if (pixels[i] !== 255) return true;
  return false;
};

// Each channel as `flattenChannel`, the same expression, so the same
// rounding: worked out once for every alpha and value, then looked up.
const flattenTable = (background) => {
  const table = new Uint8Array(256 * 256);
  for (let alpha = 0; alpha < 256; alpha++) {
    const a = alpha / 255;
    for (let c = 0; c < 256; c++) table[alpha * 256 + c] = Math.round(c * a + background * (1 - a));
  }
  return table;
};

export const flattenImpl = (pixels) => (r) => (g) => (b) => () => {
  const out = new Uint8ClampedArray(pixels.length);
  const tr = flattenTable(r);
  const tg = flattenTable(g);
  const tb = flattenTable(b);
  for (let i = 0; i < pixels.length; i += 4) {
    const row = pixels[i + 3] * 256;
    out[i] = tr[row + pixels[i]];
    out[i + 1] = tg[row + pixels[i + 1]];
    out[i + 2] = tb[row + pixels[i + 2]];
    out[i + 3] = 255;
  }
  return out;
};

// Along an axis of n picture pixels scaled to m (m <= n), scaled pixel t
// covers [t·n, (t+1)·n) and picture pixel i covers [i·m, (i+1)·m), in
// units of 1/m of a picture pixel: the overlaps are whole numbers, and
// each scaled pixel's add up to n. For t0 <= t < t1, the picture pixels
// each covers, as [i, weight, i, weight, ...].
const coverage = (n, m, t0, t1) => {
  const lists = [];
  for (let t = t0; t < t1; t++) {
    const lo = t * n;
    const hi = lo + n;
    const list = [];
    for (let i = Math.floor(lo / m); i * m < hi; i++) {
      const w = Math.min(hi, (i + 1) * m) - Math.max(lo, i * m);
      if (w > 0) list.push(i, w);
    }
    lists.push(list);
  }
  return lists;
};

// The picture (pw × ph, opaque) scaled to w × h and placed at (left, top)
// on a screen (sw × sh) filled with the background. Only the screen's
// pixels the picture covers are computed. Every sum is a whole number
// below 2^53 (at most 255 · pw · ph), so it's exact in a double and the
// same whatever the order of adding.
export const fitImpl = (pixels) => (pw) => (ph) => (sw) => (sh) => (w) => (h) => (left) => (top) => (r) => (g) => (b) => () => {
  const out = new Uint8ClampedArray(sw * sh * 4);
  for (let i = 0; i < out.length; i += 4) {
    out[i] = r;
    out[i + 1] = g;
    out[i + 2] = b;
    out[i + 3] = 255;
  }
  const x0 = Math.max(0, left);
  const x1 = Math.min(sw, left + w);
  const y0 = Math.max(0, top);
  const y1 = Math.min(sh, top + h);
  if (x0 >= x1 || y0 >= y1) return out;
  if (w === pw && h === ph) {
    // Not scaled: copied.
    for (let y = y0; y < y1; y++) {
      for (let x = x0; x < x1; x++) {
        const s = ((y - top) * pw + (x - left)) * 4;
        const d = (y * sw + x) * 4;
        out[d] = pixels[s];
        out[d + 1] = pixels[s + 1];
        out[d + 2] = pixels[s + 2];
      }
    }
    return out;
  }
  const columns = coverage(pw, w, x0 - left, x1 - left);
  const rows = coverage(ph, h, y0 - top, y1 - top);
  const visible = x1 - x0;
  const sums = new Float64Array(visible * 3);
  const total = pw * ph;
  for (let ry = 0; ry < rows.length; ry++) {
    sums.fill(0);
    const rowList = rows[ry];
    for (let k = 0; k < rowList.length; k += 2) {
      const j = rowList[k];
      const wy = rowList[k + 1];
      for (let cx = 0; cx < visible; cx++) {
        const columnList = columns[cx];
        let sr = 0;
        let sg = 0;
        let sb = 0;
        for (let q = 0; q < columnList.length; q += 2) {
          const s = (j * pw + columnList[q]) * 4;
          const wx = columnList[q + 1];
          sr += wx * pixels[s];
          sg += wx * pixels[s + 1];
          sb += wx * pixels[s + 2];
        }
        sums[cx * 3] += wy * sr;
        sums[cx * 3 + 1] += wy * sg;
        sums[cx * 3 + 2] += wy * sb;
      }
    }
    const y = y0 + ry;
    for (let cx = 0; cx < visible; cx++) {
      const d = (y * sw + x0 + cx) * 4;
      out[d] = Math.round(sums[cx * 3] / total);
      out[d + 1] = Math.round(sums[cx * 3 + 1] / total);
      out[d + 2] = Math.round(sums[cx * 3 + 2] / total);
    }
  }
  return out;
};
