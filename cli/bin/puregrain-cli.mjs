#!/usr/bin/env node
// Runs the compiled PureScript CLI (Puregrain.Cli.Main) straight from the
// workspace's shared build output. Unlike `spago run`, nothing is rebuilt
// on each run — which keeps benchmark timings free of build time.
// Build first: npm run build.
//
// PUREGRAIN_OUTPUT picks the build directory: `output` (the default, from
// purs) or `output-es` (from purs-backend-es, built by npm run build:es).

const outputDir = process.env.PUREGRAIN_OUTPUT || 'output';
const entry = new URL(`../../${outputDir}/Puregrain.Cli.Main/index.js`, import.meta.url);

let cli;
try {
  cli = await import(entry);
} catch (err) {
  if (err.code === 'ERR_MODULE_NOT_FOUND' && String(err.message).includes('Puregrain.Cli.Main')) {
    const build = outputDir === 'output-es' ? 'npm run build:es' : 'npm run build';
    console.error(`puregrain-cli is not built yet in ${outputDir}/. Run: ${build}`);
    process.exit(1);
  }
  throw err;
}
cli.main();
