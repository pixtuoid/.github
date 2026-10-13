#!/usr/bin/env bash
# Runs a command up to N times until it succeeds: retry.sh N CMD [ARGS...]
n="$1"
shift
for _ in {1..$n}; do
    "$@" && exit 0
done
exit 1
