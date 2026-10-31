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
