#!/usr/bin/env bash
# The action's own shell against fixed report files; run from the repo root.
set -euo pipefail

fail() {
    echo "upload-codecov test: $*" >&2
    exit 1
}

# ── the report gate: a run that generated nothing must not upload nothing green ──
UPLOAD_CODECOV_ACTION_FILE="${UPLOAD_CODECOV_ACTION_FILE:-.github/actions/upload-codecov/action.yml}"
require_script="$(yq -e -r '.runs.steps[] | select(.name == "Require a generated report") | .run' "$UPLOAD_CODECOV_ACTION_FILE")"

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

# ── the advisory: a missing OIDC grant is named, not blamed on Codecov ──
surface_script="$(yq -e -r '.runs.steps[] | select(.name == "Surface advisory upload failure") | .run' "$UPLOAD_CODECOV_ACTION_FILE")"

assert_advisory() {
    local oidc_url="$1"
    local expect="$2"
    local label="$3"
    local output
    output="$(env -u ACTIONS_ID_TOKEN_REQUEST_URL ${oidc_url:+ACTIONS_ID_TOKEN_REQUEST_URL="$oidc_url"} \
        REPORT_FILE=codecov.json REPORT_FLAG=unit GITHUB_STEP_SUMMARY="$work/summary" bash -c "$surface_script")"
    [[ "$output" == *"$expect"* ]] || fail "the advisory for $label says: $output"
}

assert_advisory "" "id-token: write" "a job without an OIDC grant"
assert_advisory "https://token.example" "external-service failure" "a job with an OIDC grant"
