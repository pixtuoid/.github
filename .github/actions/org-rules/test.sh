#!/usr/bin/env bash
# The action's own shell against fixed guides; run from the repo root.
set -euo pipefail

fail() {
    echo "org-rules test: $*" >&2
    exit 1
}

check_script="$(yq -e -r '.runs.steps[0].run' .github/actions/org-rules/action.yml)"
rules=.github/actions/org-rules/org-rules.md
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

assert_check() {
    local guide="$1"
    local expect="$2"
    local label="$3"
    printf '%s' "$guide" >"$work/AGENTS.md"
    if FILE="$work/AGENTS.md" RULES="$rules" bash -eo pipefail -c "$check_script" >/dev/null 2>&1; then
        [[ "$expect" == pass ]] || fail "passed $label"
    else
        [[ "$expect" == fail ]] || fail "failed $label"
    fi
}

begin='<!-- org-rules:begin -->'
end='<!-- org-rules:end -->'
copy="$(cat "$rules")"

assert_check "# Repo
$begin
$copy
$end
## The repo's own
" pass "a verbatim copy with the repo's own rules around it"
assert_check "$begin
$copy
- one more line
$end
" fail "a copy that gained a line"
assert_check "$begin
${copy/Never force-push/Sometimes force-push}
$end
" fail "a copy that changed a word"
assert_check "$begin
$copy

$end
" fail "a copy with a blank line gained before the end marker"
assert_check "# Repo, no markers
$copy
" fail "a guide without the markers"
assert_check "$begin
$copy
$end
$begin
$copy
$end
" fail "two copies"
assert_check "$end
$copy
$begin
" fail "the markers in the wrong order"
assert_check "$begin
$end
" fail "an empty copy"
FILE="$work/missing.md" RULES="$rules" bash -eo pipefail -c "$check_script" >/dev/null 2>&1 && fail "passed a missing guide"
echo "org-rules: 9 cases"
