// Reusable drawing primitives for generating grayscale PNG test fixtures.
// All functions mutate `png.data` (RGBA buffer) in place.

export function setPixel(png, x, y, v) {
  const idx = (y * png.width + x) * 4;
  png.data[idx] = v;
  png.data[idx + 1] = v;
  png.data[idx + 2] = v;
  png.data[idx + 3] = 255;
}

export function drawHorizontalGradient(png) {
  const { width, height } = png;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const v = Math.round((255 * x) / (width - 1));
      setPixel(png, x, y, v);
    }
  }
}

export function drawShadedCircle(png, cx, cy, r) {
  const y0 = Math.max(0, Math.floor(cy - r));
  const y1 = Math.min(png.height, Math.ceil(cy + r));
  const x0 = Math.max(0, Math.floor(cx - r));
  const x1 = Math.min(png.width, Math.ceil(cx + r));

  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      const d = Math.hypot(x - cx, y - cy) / r;
      if (d <= 1) {
        const v = Math.round(255 * Math.pow(Math.max(0, 1 - d), 0.5));
        setPixel(png, x, y, v);
      }
    }
  }
}

export function drawFlatToneBands(png, levels, yTop, yBottom) {
  const { width } = png;
  const boxW = Math.floor(width / levels.length);
  for (let i = 0; i < levels.length; i++) {
    const xStart = i * boxW;
    const xEnd = i === levels.length - 1 ? width : xStart + boxW;
    for (let y = yTop; y < yBottom; y++) {
      for (let x = xStart; x < xEnd; x++) {
        setPixel(png, x, y, levels[i]);
      }
    }
  }
}

export function drawRect(png, x0, y0, x1, y1, v) {
  for (let y = y0; y < y1; y++) {
    for (let x = x0; x < x1; x++) {
      setPixel(png, x, y, v);
    }
  }
}

export function drawLine(png, x0, y0, x1, y1, v) {
  // simple Bresenham-ish stepper, sufficient for a thin diagnostic line
  const steps = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
  for (let i = 0; i <= steps; i++) {
    const t = steps === 0 ? 0 : i / steps;
    const x = Math.round(x0 + (x1 - x0) * t);
    const y = Math.round(y0 + (y1 - y0) * t);
    setPixel(png, x, y, v);
  }
}