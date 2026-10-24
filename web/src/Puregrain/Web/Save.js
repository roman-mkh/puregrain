// Saving the result as files: a canvas's pixels as a PNG (`toBlob`), or
// a machine's file from its bytes, each saved by a link with a `download`
// name. The link isn't added to the page: an `a` element follows its link
// unconnected too, by the HTML standard ("cannot navigate").

const saveBlob = (blob, name) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = name;
  link.click();
  // The download fetches the file after the click has returned, so the
  // URL is revoked later, as FileSaver.js does (after 40 s).
  setTimeout(() => URL.revokeObjectURL(url), 40000);
};

export const savePngImpl = (canvas) => (name) => () =>
  new Promise((resolve) => {
    canvas.toBlob((blob) => {
      // null when the browser couldn't make the PNG.
      if (blob === null) {
        resolve(false);
        return;
      }
      saveBlob(blob, name);
      resolve(true);
    }, "image/png");
  });

export const saveBytes = (bytes) => (name) => () =>
  saveBlob(new Blob([bytes], { type: "application/octet-stream" }), name);
