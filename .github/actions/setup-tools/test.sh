#!/usr/bin/env bash
# The action's own shell, and the mise-action inputs no run shows wrong; run
# from the repo root.
set -euo pipefail

fail() {
    echo "setup-tools test: $*" >&2
    exit 1
}

action=.github/actions/setup-tools/action.yml
enable_script="$(yq -e -r '.runs.steps[0].run' "$action")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The GITHUB_ENV line the step writes for `tools: $1`, or "failed".
enabled() {
    : >"$work/env"
    TOOLS="$1" GITHUB_ENV="$work/env" bash -eo pipefail -c "$enable_script" >/dev/null 2>&1 || {
        echo failed
        return
    }
    cat "$work/env"
}

[[ "$(enabled 'just,aqua:rhysd/actionlint')" == 'MISE_ENABLE_TOOLS=just,aqua:rhysd/actionlint' ]] ||
    fail "the tools are not mise's allowlist as given"
# `required: true` is advisory, and an empty allowlist would let mise resolve
# every configured tool.
[[ "$(enabled '')" == failed ]] || fail "an empty tools passed"

# Every ref restores main's cache, so a save from another ref only evicts
# main's entries, with nothing red; and the default key leaves the tool set
# out, so jobs with other sets would share one entry.
with='.runs.steps[] | select(.uses // "" | test("^jdx/mise-action@")) | .with'
# shellcheck disable=SC2016 # the literal GitHub expression syntax
[[ "$(yq -r "$with.cache_save" "$action")" == '${{ github.ref == '"'refs/heads/main'"' }}' ]] ||
    fail "the mise cache is saved from a ref other than main"
# shellcheck disable=SC2016 # the literal GitHub expression syntax
[[ "$(yq -r "$with.cache_key" "$action")" == '{{default}}-${{ inputs.tools }}' ]] ||
    fail "the mise cache key leaves out the tool set"
