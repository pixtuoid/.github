#!/usr/bin/env bash
# The action's own shell against fixed needs-maps; run from the repo root.
set -euo pipefail

fail() {
    echo "require-jobs test: $*" >&2
    exit 1
}

# ── require-jobs: the verdict ci-gate and every group's `required` job reach ──
# Anything but success is red, and an empty needs map must not pass vacuously.
require_script="$(yq -e -r '.runs.steps[0].run' .github/actions/require-jobs/action.yml)"

assert_required() {
    local results="$1"
    local expect="$2"
    local label="$3"
    local allow_skipped="${4:-false}"
    if RESULTS="$results" LABEL=selftest ALLOW_SKIPPED="$allow_skipped" bash -eo pipefail -c "$require_script" >/dev/null 2>&1; then
        [[ "$expect" == pass ]] || fail "require-jobs passed $label"
    else
        [[ "$expect" == fail ]] || fail "require-jobs failed $label"
    fi
}

assert_required '{"a":{"result":"success"},"b":{"result":"success"}}' pass "every needed job succeeding"
assert_required '{"a":{"result":"success"},"b":{"result":"failure"}}' fail "a failed job"
assert_required '{"a":{"result":"success"},"b":{"result":"skipped"}}' fail "a skipped job"
assert_required '{"a":{"result":"success"},"b":{"result":"cancelled"}}' fail "a cancelled job"
assert_required '{}' fail "an empty needs map"
assert_required '' fail "no results at all"
# The light tier: its full-only jobs skip by design, nothing else passes.
assert_required '{"a":{"result":"success"},"b":{"result":"skipped"}}' pass "a light-tier skip" true
assert_required '{"a":{"result":"success"},"b":{"result":"failure"}}' fail "a light-tier failure" true
assert_required '{"a":{"result":"success"},"b":{"result":"cancelled"}}' fail "a light-tier cancel" true
