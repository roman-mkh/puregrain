#!/usr/bin/env node
// Runs the compiled PureScript CLI (Puregrain.Cli.Main) straight from the
// workspace's shared build output. Unlike `spago run`, nothing is rebuilt
// on each run — which keeps benchmark timings free of build time.
// Build first: npm run build.

const entry = new URL('../../output/Puregrain.Cli.Main/index.js', import.meta.url);

let cli;
try {
  cli = await import(entry);
} catch (err) {
  if (err.code === 'ERR_MODULE_NOT_FOUND' && String(err.message).includes('Puregrain.Cli.Main')) {
    console.error('puregrain-cli is not built yet. Run: npm run build');
    process.exit(1);
  }
  throw err;
}
cli.main();
