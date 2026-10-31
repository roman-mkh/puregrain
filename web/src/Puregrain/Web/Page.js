// The page around the app: the system's theme, the theme on the page's
// root element, and the library's version from the meta element that
// web/build.mjs fills in.

export const prefersDark = () => window.matchMedia('(prefers-color-scheme: dark)').matches;

export const setTheme = (name) => () => {
  document.documentElement.dataset.theme = name;
};

export const libraryVersion = () =>
  document.querySelector('meta[name="puregrain-version"]')?.content ?? '';
