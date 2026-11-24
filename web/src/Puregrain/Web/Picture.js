// Decoding a picture file in the browser, without color conversion
// (decision 9 in web/ROADMAP.md) and without premultiplying its colors by
// alpha, a canvas to read its pixels from, and an <img> through WebGL to
// read a picture with transparency exactly (decision 27).

export const decodeImpl = (file) => () =>
  createImageBitmap(file, { colorSpaceConversion: "none", premultiplyAlpha: "none" });

export const bitmapWidth = (bitmap) => bitmap.width;

export const bitmapHeight = (bitmap) => bitmap.height;

export const closeBitmap = (bitmap) => () => bitmap.close();

export const newCanvas = () => document.createElement("canvas");

// A file from the page's own site, such as the sample picture, wrapped as a
// File of the given name, so that it loads as a chosen file does. Fails when
// it can't be fetched.
export const fetchFileImpl = (path) => (name) => () =>
  fetch(path)
    .then((response) => (response.ok ? response.blob() : Promise.reject(new Error(`${path}: ${response.status}`))))
    .then((blob) => new File([blob], name, { type: blob.type }));

// The picture again as an <img> element, for reading its transparency
// exactly: decoded from the same file.
export const decodeImageImpl = (file) => () => {
  const image = new Image();
  image.src = URL.createObjectURL(file);
  return image.decode().then(() => image, (error) => {
    URL.revokeObjectURL(image.src);
    throw error;
  });
};

// The picture's RGBA bytes as stored: the <img> uploaded as a texture that
// isn't premultiplied and has no color conversion, read back from a
// framebuffer. Not from the ImageBitmap: WebKit keeps a bitmap premultiplied
// whatever it's asked, so its semi-transparent colors come back off, by up to
// 254 (found 2026-11-15 in Playwright's WebKit 27.2), while for an <img> the
// browsers decode the file again unpremultiplied; exact in Chromium 156,
// Firefox 157 and WebKit 27.2. Accepted only if it agrees with the 2D
// canvas's bytes (`fromCanvas`), which are exact for every alpha and for
// the colors of opaque pixels: same size, every alpha, every opaque color,
// so a browser that rotated or converted the two differently falls back to
// the canvas. Nothing, too, when WebGL isn't there, the picture is larger
// than a texture may be, or anything fails.
export const exactRgbaImpl = (just) => (nothing) => (image) => (width) => (height) => (fromCanvas) => () => {
  const gl = document.createElement("canvas").getContext("webgl");
  try {
    if (gl === null) return nothing;
    if (image.naturalWidth !== width || image.naturalHeight !== height) return nothing;
    const max = gl.getParameter(gl.MAX_TEXTURE_SIZE);
    if (width > max || height > max) return nothing;
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.pixelStorei(gl.UNPACK_COLORSPACE_CONVERSION_WEBGL, gl.NONE);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, image);
    gl.bindFramebuffer(gl.FRAMEBUFFER, gl.createFramebuffer());
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) return nothing;
    const out = new Uint8Array(width * height * 4);
    gl.readPixels(0, 0, width, height, gl.RGBA, gl.UNSIGNED_BYTE, out);
    if (gl.getError() !== gl.NO_ERROR) return nothing;
    for (let i = 0; i < out.length; i += 4) {
      if (out[i + 3] !== fromCanvas[i + 3]) return nothing;
      if (out[i + 3] === 255 && (out[i] !== fromCanvas[i] || out[i + 1] !== fromCanvas[i + 1] || out[i + 2] !== fromCanvas[i + 2])) return nothing;
    }
    return just(new Uint8ClampedArray(out.buffer));
  } catch (e) {
    return nothing;
  } finally {
    URL.revokeObjectURL(image.src);
    const lose = gl === null ? null : gl.getExtension("WEBGL_lose_context");
    if (lose !== null) lose.loseContext();
  }
};

// The same file under another name.
export const namedImpl = (name) => (file) => new File([file], name, { type: file.type });

// The first picture on the clipboard, as a file, or nothing; fails when
// the browser doesn't let the page read the clipboard (or has no
// navigator.clipboard, as outside a secure context), with an Error whose
// message keeps the browser's reason and its name (a DOMException's,
// "NotAllowedError", would otherwise be lost).
export const readClipboardImpl = (just) => (nothing) => () =>
  Promise.resolve().then(() => navigator.clipboard.read()).catch((e) => {
    throw new Error(`${e?.name ?? 'Error'}: ${e?.message ?? e}`);
  }).then(async (items) => {
    for (const item of items) {
      const type = item.types.find((t) => t.startsWith('image/'));
      if (type !== undefined) {
        const blob = await item.getType(type);
        return just(new File([blob], 'image.png', { type: blob.type }));
      }
    }
    return nothing;
  });
