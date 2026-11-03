// The page around the app: the system's theme, the theme on the page's
// root element, the library's version from the meta element that
// web/build.mjs fills in, and whether the layout is a phone's.

export const prefersDark = () => window.matchMedia('(prefers-color-scheme: dark)').matches;

export const setTheme = (name) => () => {
  document.documentElement.dataset.theme = name;
};

export const libraryVersion = () =>
  document.querySelector('meta[name="puregrain-version"]')?.content ?? '';

// The same limit as app.css's phone layout.
export const narrowScreen = () => window.matchMedia('(max-width: 760px)').matches;

// A file fetched once and kept in memory for the page's lifetime, under an
// address of its own (a Blob URL, never revoked); the file's own address
// when it can't be fetched.
export const keptInMemoryImpl = (path) => () =>
  fetch(path)
    .then((response) => (response.ok ? response.blob() : Promise.reject(new Error(response.statusText))))
    .then((blob) => URL.createObjectURL(blob))
    .catch(() => path);
