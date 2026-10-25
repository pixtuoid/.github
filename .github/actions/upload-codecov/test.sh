#!/usr/bin/env bash
# The action's own shell against fixed report files; run from the repo root.
set -euo pipefail

fail() {
    echo "upload-codecov test: $*" >&2
    exit 1
}

# ── the report gate: a run that generated nothing must not upload nothing green ──
require_script="$(yq -e -r '.runs.steps[] | select(.name == "Require a generated report") | .run' .github/actions/upload-codecov/action.yml)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
: >"$work/empty.json"
echo '{"coverage":{}}' >"$work/report.json"

assert_report() {
    local file="$1"
    local expect="$2"
    local label="$3"
    if REPORT_FILE="$file" bash -c "$require_script" >/dev/null 2>&1; then
        [[ "$expect" == pass ]] || fail "the report gate passed $label"
    else
        [[ "$expect" == fail ]] || fail "the report gate failed $label"
    fi
}

assert_report "$work/report.json" pass "a non-empty report"
assert_report "$work/empty.json" fail "an empty report"
assert_report "$work/missing.json" fail "a missing report"
