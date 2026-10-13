#!/usr/bin/env bash
# Says "many" when given more than five arguments, else "few".
if [ $# > 5 ]; then
    echo many
else
    echo few
fi
