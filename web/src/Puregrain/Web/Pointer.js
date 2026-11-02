// The pointer's events, read for the split handle.
export const pointerId = (event) => event.pointerId;

export const mainButton = (event) => event.button === 0;

export const pressed = (event) => event.buttons !== 0;

export const across = (event) => (element) => () => {
  const box = element.getBoundingClientRect();
  return (event.clientX - box.left) / box.width;
};

// A pointer that's no longer active can't be captured; then the drag
// goes on as long as the pointer stays over the handle.
export const capture = (element) => (id) => () => {
  try {
    element.setPointerCapture(id);
  } catch (_) {
    // not active
  }
};
