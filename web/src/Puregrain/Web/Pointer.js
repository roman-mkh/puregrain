// The pointer's events, read for the split handle.
export const pointerId = (event) => event.pointerId;

export const mainButton = (event) => event.button === 0;

export const pressed = (event) => event.buttons !== 0;

export const across = (event) => (element) => () => {
  const box = element.getBoundingClientRect();
  return (event.clientX - box.left) / box.width;
};

// A pointer that's no longer active can't be captured; then the drag
// goes on as long as the pointer stays over the handle. While it's
// captured, no text selection starts: WebKit (Safari) would stretch one
// from the press over the pictures and the page's text, capture and the
// handle's user-select notwithstanding (Chromium and Firefox select
// nothing). The capture's end, `lostpointercapture`, reaches the document
// however it ends: released, cancelled, or the handle gone.
export const capture = (element) => (id) => () => {
  try {
    element.setPointerCapture(id);
  } catch (_) {
    return; // not active
  }
  const noSelection = (event) => event.preventDefault();
  const release = (event) => {
    if (event.pointerId !== id) return;
    document.removeEventListener("selectstart", noSelection);
    document.removeEventListener("lostpointercapture", release);
  };
  document.addEventListener("selectstart", noSelection);
  document.addEventListener("lostpointercapture", release);
};
