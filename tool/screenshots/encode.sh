#!/bin/sh
# Encodes the PNGs rendered by screenshots_test.dart into screenshots/*.webp.
set -e
cd "$(dirname "$0")/../.."
for pair in request_list:in_flight request_actions:request_actions compare:compare; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  cwebp -quiet -q 85 "build/screenshots/$src.png" -o "screenshots/$dst.webp"
done
ls -la screenshots
