// Decoding a picture file in the browser, without color conversion
// (decision 9 in web/ROADMAP.md) and without premultiplying its colors by
// alpha, a canvas to read its pixels from, and WebGL to read a picture
// with transparency exactly (decision 27).

export const decodeImpl = (file) => () =>
  createImageBitmap(file, { colorSpaceConversion: "none", premultiplyAlpha: "none" });

export const bitmapWidth = (bitmap) => bitmap.width;

export const bitmapHeight = (bitmap) => bitmap.height;

export const closeBitmap = (bitmap) => () => bitmap.close();

export const newCanvas = () => document.createElement("canvas");

// The bitmap's RGBA bytes as decoded: a texture that isn't premultiplied,
// read back from a framebuffer. Nothing when WebGL isn't there, the
// picture is larger than a texture may be, or anything fails.
export const exactRgbaImpl = (just) => (nothing) => (bitmap) => () => {
  const gl = document.createElement("canvas").getContext("webgl");
  if (gl === null) return nothing;
  try {
    const max = gl.getParameter(gl.MAX_TEXTURE_SIZE);
    if (bitmap.width > max || bitmap.height > max) return nothing;
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, bitmap);
    gl.bindFramebuffer(gl.FRAMEBUFFER, gl.createFramebuffer());
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) return nothing;
    const out = new Uint8Array(bitmap.width * bitmap.height * 4);
    gl.readPixels(0, 0, bitmap.width, bitmap.height, gl.RGBA, gl.UNSIGNED_BYTE, out);
    if (gl.getError() !== gl.NO_ERROR) return nothing;
    return just(new Uint8ClampedArray(out.buffer));
  } catch (e) {
    return nothing;
  } finally {
    const lose = gl.getExtension("WEBGL_lose_context");
    if (lose !== null) lose.loseContext();
  }
};
