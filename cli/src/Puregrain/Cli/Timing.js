// The clock around the dithering. See Timing.purs for why it's foreign.
export const timed = (f) => (x) => () => {
  const t0 = performance.now();
  const result = f(x);
  const ms = performance.now() - t0;
  return { ms, result };
};
