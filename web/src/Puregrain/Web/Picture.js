// Decoding a picture file in the browser, without color conversion
// (decision 9 in web/ROADMAP.md), and a canvas to read its pixels from.

export const decodeImpl = (file) => () =>
  createImageBitmap(file, { colorSpaceConversion: "none" });

export const bitmapWidth = (bitmap) => bitmap.width;

export const bitmapHeight = (bitmap) => bitmap.height;

export const closeBitmap = (bitmap) => () => bitmap.close();

export const newCanvas = () => document.createElement("canvas");
