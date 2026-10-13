#!/usr/bin/env bash
# Says "many" when given more than five arguments, else "few".
# Usage: count.sh [ARG...]
if [ $# > 5 ]; then
    echo many
else
    echo few
fi
