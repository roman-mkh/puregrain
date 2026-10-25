// RGBA bytes for PrepareSpec, from plain numbers and back.

export const rgbaOf = (values) => () => Uint8ClampedArray.from(values);

export const valuesOf = (pixels) => () => Array.from(pixels);
