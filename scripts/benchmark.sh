#!/usr/bin/env bash
scriptDir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
npm run generate-bench-images
echo "images has been generated. starting benchmark dithering"
for s in 64 128 256 512 1024; do
  echo "=== size $s ==="
  time node ${scriptDir}/dither-cli.mjs ${scriptDir}/../samples/bench/bench-$s.png /tmp/out-$s.png floyd-steinberg
done