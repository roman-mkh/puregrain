// Saving a canvas's pixels as a PNG file: the canvas encodes them
// (`toBlob`), and a link with a `download` name saves the file. The link
// isn't added to the page: an `a` element follows its link unconnected
// too, by the HTML standard ("cannot navigate").

export const savePngImpl = (canvas) => (name) => () =>
  new Promise((resolve) => {
    canvas.toBlob((blob) => {
      // null when the browser couldn't make the PNG.
      if (blob === null) {
        resolve(false);
        return;
      }
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = name;
      link.click();
      // The download fetches the file after the click has returned, so
      // the URL is revoked later, as FileSaver.js does (after 40 s).
      setTimeout(() => URL.revokeObjectURL(url), 40000);
      resolve(true);
    }, "image/png");
  });
