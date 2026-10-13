#!/usr/bin/env bash
# Greets each name given, then reports how many it greeted.
set -euo pipefail
shopt -s lastpipe
count=0
for name in "$@"; do
    echo "hello, $name"
    count=$((count + 1))
done | cat
echo "greeted $count names"
