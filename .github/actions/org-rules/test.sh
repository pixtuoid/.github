#!/usr/bin/env bash
# The action's own shell against fixed guides and stubs; run from the repo
# root, the stubs' source.
set -euo pipefail

fail() {
    echo "org-rules test: $*" >&2
    exit 1
}

step() { yq -e -r ".runs.steps[] | select(.name == \"$1\") | .run" .github/actions/org-rules/action.yml; }
check_script="$(step guide)"
config_script="$(step shared-config)"
# The shared-config step's env but its ${{ }} values, which each case sets.
config_env=()
while IFS= read -r -d '' kv; do config_env+=("$kv"); done < <(
    yq -o=json '.runs.steps[] | select(.name == "shared-config") | .env' .github/actions/org-rules/action.yml |
        jq -j 'to_entries[] | select(.value | contains("${{") | not) | "\(.key)=\(.value)\u0000"')
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

# A fixture repo named $1 under $work, its path printed, holding every stub
# the shared-config step requires.
stub_repo() {
    local repo="$work/stubs-$1"
    mkdir -p "$repo/.github/workflows" "$repo/.claude"
    cp .github/workflows/review.yml "$repo/.github/workflows/review.yml"
    cp .claude/settings.json "$repo/.claude/settings.json"
    echo 'extends: .github' >"$repo/.mergify.yml"
    echo "$repo"
}
# assert_config <repo> <name> <pass|fail> <label> [source, this checkout unless given]
assert_config() {
    local repo="$1" name="$2" expect="$3" label="$4" source="${5:-$PWD}"
    if (cd "$repo" && env "${config_env[@]}" SOURCE="$source" REPO="pixtuoid/$name" bash -eo pipefail -c "$config_script") >"$work/config.out" 2>&1; then
        [[ "$expect" == pass ]] || fail "passed $label"
    else
        [[ "$expect" == fail ]] || fail "failed $label: $(cat "$work/config.out")"
    fi
}

assert_config "$(stub_repo ok)" lofi pass "a repo holding every stub as the step requires"
repo="$(stub_repo extra-concurrency)"
yq -i '.concurrency = {"group": "claude-review", "cancel-in-progress": true}' "$repo/.github/workflows/review.yml"
assert_config "$repo" lofi fail "a review caller that gained a concurrency block"
repo="$(stub_repo no-caller)"
rm "$repo/.github/workflows/review.yml"
assert_config "$repo" lofi fail "a repo with no review caller"
repo="$(stub_repo no-mergify)"
rm "$repo/.mergify.yml"
assert_config "$repo" lofi fail "a repo with no .mergify.yml"
repo="$(stub_repo own-queue)"
printf 'queue_rules:\n  - name: default\n' >"$repo/.mergify.yml"
assert_config "$repo" lofi fail "a .mergify.yml that extends nothing"
repo="$(stub_repo source)"
printf 'queue_rules:\n  - name: default\n' >"$repo/.mergify.yml"
assert_config "$repo" .github pass "the source's own .mergify.yml, which Mergify lets extend nothing"
repo="$(stub_repo no-settings)"
rm "$repo/.claude/settings.json"
assert_config "$repo" lofi fail "a repo with no .claude/settings.json"
repo="$(stub_repo plugin-off)"
jq '.enabledPlugins |= map_values(false)' .claude/settings.json >"$repo/.claude/settings.json"
assert_config "$repo" lofi fail "settings that disable the org's plugin"
repo="$(stub_repo no-auto-update)"
jq '.extraKnownMarketplaces |= map_values(del(.autoUpdate))' .claude/settings.json >"$repo/.claude/settings.json"
assert_config "$repo" lofi fail "settings whose marketplace entry differs from the source's"
repo="$(stub_repo own-settings)"
jq '.permissions.deny = ["Bash(gh pr merge *)"] | .enabledPlugins["other@elsewhere"] = true' .claude/settings.json >"$repo/.claude/settings.json"
assert_config "$repo" lofi pass "settings that add the repo's own keys"
repo="$(stub_repo coderabbit-yaml)"
touch "$repo/.coderabbit.yaml"
assert_config "$repo" lofi fail "a repo-level .coderabbit.yaml"
repo="$(stub_repo coderabbit-ts)"
touch "$repo/.coderabbit.config.ts"
assert_config "$repo" lofi fail "a repo-level .coderabbit.config.ts"
# A repo's own merge_conditions or queue_conditions list replaces the org's whole.
repo="$(stub_repo own-conditions)"
yq -n '.extends = ".github" | .queue_rules = [{"name": "default",
    "queue_conditions": load(".mergify.yml").defaults.queue_rule.queue_conditions + ["label = ready"],
    "merge_conditions": load(".mergify.yml").defaults.queue_rule.merge_conditions + ["check-success = full-gate"]}]' >"$repo/.mergify.yml"
assert_config "$repo" apple pass "a default rule whose conditions add to the org's"
repo="$(stub_repo dropped-queue-condition)"
yq -n '.extends = ".github" | .queue_rules = [{"name": "default", "queue_conditions": load(".mergify.yml").defaults.queue_rule.queue_conditions | .[1:]}]' >"$repo/.mergify.yml"
assert_config "$repo" apple fail "a default rule whose queue_conditions drop one of the org's"
repo="$(stub_repo dropped-condition)"
yq -n '.extends = ".github" | .queue_rules = [{"name": "default", "merge_conditions": (load(".mergify.yml").defaults.queue_rule.merge_conditions | .[1:]) + ["check-success = full-gate"]}]' >"$repo/.mergify.yml"
assert_config "$repo" apple fail "a default rule whose merge_conditions drop one of the org's"
repo="$(stub_repo dropped-default)"
yq -n '.extends = ".github" | .defaults.queue_rule.merge_conditions = ["check-success = full-gate"]' >"$repo/.mergify.yml"
assert_config "$repo" apple fail "local defaults whose merge_conditions drop the org's"
# The org's queue keeps a release PR out by its branch's prefix.
repo="$(stub_repo release-plz-default)"
printf '[workspace]\n\n[[package]]\nname = "a"\n' >"$repo/release-plz.toml"
assert_config "$repo" lofi pass "a release-plz.toml on release-plz's default prefix"
repo="$(stub_repo release-plz-moved)"
printf '[workspace]\npr_branch_prefix = "release-"\n' >"$repo/release-plz.toml"
assert_config "$repo" pixtuoid fail "a release-plz.toml whose prefix the org's queue lets in"
repo="$(stub_repo release-plz-config-dir)"
mkdir -p "$repo/.config" && printf '[workspace]\npr_branch_prefix = "release-"\n' >"$repo/.config/release-plz.toml"
assert_config "$repo" pixtuoid fail "a .config/release-plz.toml whose prefix the org's queue lets in"
repo="$(stub_repo release-plz-dotfile)"
printf '[workspace]\npr_branch_prefix = "release-"\n' >"$repo/.release-plz.toml"
assert_config "$repo" pixtuoid fail "a .release-plz.toml whose prefix the org's queue lets in"
# The source checks itself: a queue config it lost or emptied passes nothing.
repo="$(stub_repo source-no-queue)"
rm "$repo/.mergify.yml"
assert_config "$repo" .github fail "the source with no .mergify.yml" "$repo"
repo="$(stub_repo source-empty-queue)"
: >"$repo/.mergify.yml"
assert_config "$repo" .github fail "the source with an empty .mergify.yml" "$repo"
repo="$(stub_repo source-itself)"
cp .mergify.yml "$repo/.mergify.yml"
assert_config "$repo" .github pass "the source checking its own .mergify.yml" "$repo"
