#!/usr/bin/env bash
scriptDir=$(dirname -- "$(readlink -f -- "$BASH_SOURCE")")
node ${scriptDir}/generate-images.mjs --pattern gray --sizes 64,128,256,512,1024 --out ${scriptDir}/../samples/bench
echo "images has been generated. starting benchmark dithering"
for s in 64 128 256 512 1024; do
  echo "=== size $s ==="
  time node ${scriptDir}/dither-cli.mjs ${scriptDir}/../samples/bench/gray-$s.png /tmp/out-$s.png floyd-steinberg
done
