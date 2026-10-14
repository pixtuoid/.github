#!/usr/bin/env bash
# claude-review.yml's scope step against fixed API pages; run from the repo root.
set -euo pipefail

fail() {
    echo "claude-review test: $*" >&2
    exit 1
}

WORKFLOW_FILE="${CLAUDE_REVIEW_WORKFLOW_FILE:-.github/workflows/claude-review.yml}"
step='.jobs.claude-review.steps[] | select(.id == "scope")'
script="$(yq -e -r "$step | .run" "$WORKFLOW_FILE")"
verdicts_jq="$(yq -e -r "$step | .env.VERDICTS" "$WORKFLOW_FILE")"
comment_jq="$(yq -e -r "$step | .env.COMMENT" "$WORKFLOW_FILE")"
recheck_jq="$(yq -e -r "$step | .env.RECHECK" "$WORKFLOW_FILE")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Serves $PAGES/<kind>.<n>.json in page order, each through --jq as gh does,
# and only page 1 without --paginate; anything else is a call the step must
# not make.
gh() {
    local paginate=false path="" expr="" kind
    [[ "${1:-}" == api ]] || { echo "gh stub: unexpected: $*" >&2; return 1; }
    shift
    while (($#)); do
        case "$1" in
        --paginate) paginate=true ;;
        --jq) expr="$2"; shift ;;
        -*) echo "gh stub: unexpected flag $1" >&2; return 1 ;;
        *) path="$1" ;;
        esac
        shift
    done
    case "$path" in
    "repos/$GITHUB_REPOSITORY/pulls/$PR/commits?per_page=100") kind=commits ;;
    "repos/$GITHUB_REPOSITORY/pulls/$PR/reviews?per_page=100") kind=reviews ;;
    "repos/$GITHUB_REPOSITORY/pulls/$PR/comments?per_page=100") kind=comments ;;
    *) echo "gh stub: unexpected path $path" >&2; return 1 ;;
    esac
    local page=1
    while [[ -f "$PAGES/$kind.$page.json" ]]; do
        jq -rcS "$expr" "$PAGES/$kind.$page.json" || return
        $paginate || break
        page=$((page + 1))
    done
}
export -f gh

sha() { printf '%040d' "$1"; }
at() { printf '2026-01-01T00:%02d:00Z' "$1"; }
commit() { jq -nc --arg sha "$(sha "$1")" '{sha: $sha}'; }
# review <author> <commit> <body> [minute submitted, default the commit's number]
review() {
    jq -nc --arg by "$1" --arg sha "$(sha "$2")" --arg body "$3" --arg at "$(at "${4:-$2}")" \
        '{user: {login: $by}, commit_id: $sha, body: $body, submitted_at: $at}'
}
# comment <id> <body> [id it replies to] [minute created, default the id]
comment() {
    jq -nc --argjson id "$1" --arg body "$2" --argjson to "${3:-null}" --arg at "$(at "${4:-$1}")" \
        '{id: $id, in_reply_to_id: $to, created_at: $at, user: {login: "github-actions[bot]"}, path: "a.rs", line: null, original_line: 7, body: $body, diff_hunk: "@@"}'
}
page() { jq -sc . >"$PAGES/$1.$2.json"; }

# Runs the step over the pages a case wrote and sets $since, $comments and
# $recheck.
run_step() {
    local out="$work/$1.out"
    : >"$out"
    PAGES="$PAGES" GITHUB_REPOSITORY=org/repo PR=7 RUNNER_TEMP="$work/$1.tmp" GITHUB_OUTPUT="$out" \
        VERDICTS="$verdicts_jq" COMMENT="$comment_jq" RECHECK="$recheck_jq" \
        bash --noprofile --norc -eo pipefail -c "$script" || fail "$1: the step failed"
    since="$(sed -n 's/^since=//p' "$out")"
    comments="$(sed -n 's/^comments=//p' "$out")"
    recheck="$(sed -n 's/^recheck=//p' "$out")"
    [[ -f "$comments" ]] || fail "$1: no comments file at '$comments'"
    [[ -f "$recheck" ]] || fail "$1: no recheck file at '$recheck'"
}

# The finding ids of the recheck file, each with its replies' ids.
assert_recheck() {
    local name="$1" want="$2" got
    run_step "$name"
    got="$(jq -c -s 'map([.finding.id, (.replies | map(.id))])' "$recheck")"
    [[ "$got" == "$want" ]] || fail "$name: recheck $got, want $want"
}

new_case() {
    PAGES="$work/$1"
    mkdir -p "$PAGES"
    for kind in commits reviews comments; do printf '' | page "$kind" 1; done
}

assert_since() {
    local name="$1" want="$2"
    run_step "$name"
    [[ "$since" == "$want" ]] || fail "$name: since '$since', want '$want'"
}

bot='github-actions[bot]'

new_case first
{ commit 1; commit 2; } | page commits 1
assert_since first ""

# The MCP tool's one page was what hid pixtuoid#1648's newest reviews.
new_case newest-on-page-2
commit 1 | page commits 1
{ commit 2; commit 3; } | page commits 2
review "$bot" 1 'Blocking: 0' | page reviews 1
review "$bot" 2 $'Blocking: 1\n\n**Verdict:** one blocking finding' | page reviews 2
assert_since newest-on-page-2 "$(sha 2)"

new_case force-pushed
{ commit 1; commit 3; } | page commits 1
{ review "$bot" 1 'Blocking: 0'; review "$bot" 2 'Blocking: 0'; } | page reviews 1
assert_since force-pushed "$(sha 1)"

new_case rebased
{ commit 3; commit 4; } | page commits 1
{ review "$bot" 1 'Blocking: 0'; review "$bot" 2 'Blocking: 0'; } | page reviews 1
assert_since rebased ""

new_case no-verdict
{ commit 1; commit 2; commit 3; commit 4; } | page commits 1
{
    review "$bot" 1 'Blocking: 0'
    review "$bot" 2 ''
    review "$bot" 3 $'**Verdict:** fine\nBlocking: 0'
    review "$bot" 4 'Blocking: incomplete'
} | page reviews 1
assert_since no-verdict "$(sha 1)"

new_case human
{ commit 1; commit 2; } | page commits 1
{ review "$bot" 1 'Blocking: 0'; review someone 2 'Blocking: 0'; } | page reviews 1
assert_since human "$(sha 1)"

# The MCP tool stops at 100 comments, the oldest, so the newest round's
# findings were the ones a re-review could not see.
new_case comments
{ comment 1 $'**blocking**: first\nsecond line'; comment 2 'old'; } | page comments 1
comment 3 'newest' | page comments 2
run_step comments
[[ "$(wc -l <"$comments" | tr -d ' ')" == 3 ]] || fail "comments: want 3 lines, got: $(cat "$comments")"
jq -e -s '[.[].body] == ["**blocking**: first\nsecond line", "old", "newest"]
    and .[0].line == 7 and .[0].path == "a.rs" and .[0].user == "github-actions[bot]"
    and (.[0] | has("diff_hunk") | not)' "$comments" >/dev/null ||
    fail "comments: wrong lines: $(cat "$comments")"

# Before a second verdict every reply is one no review has checked.
new_case recheck-first
{ comment 1 'finding'; comment 2 'finding'; comment 3 'FIXED in x' 2; } | page comments 1
assert_recheck recheck-first '[[2,[3]]]'

# The review before the last was submitted at minute 20, so the last one read
# the comments after it: a reply at 25, while the last review ran, is still
# unchecked, and one at 15 was checked.
new_case recheck-window
{ commit 1; commit 2; commit 3; } | page commits 1
{ review "$bot" 1 'Blocking: 1' 10; review "$bot" 2 'Blocking: 0' 20; review "$bot" 3 'Blocking: 0' 30; } | page reviews 1
{
    comment 1 'a'
    comment 2 'FIXED' 1 15
    comment 3 'b'
    comment 4 'FIXED' 3 25
    comment 5 'c'
    comment 6 'FIXED' 5 35
    comment 7 'd'
    comment 8 'FIXED' 7 12
    comment 9 'still broken?' 7 40
} | page comments 1
assert_recheck recheck-window '[[3,[4]],[5,[6]],[7,[9]]]'

# The diff step, over a real repo: base b, the PR's commits p1 and p2, then a
# merge of the base's next commit b2, resolving their conflict in a; the base
# then moves on to b3, and the checkout past the event's head to p3.
diff_script="$(yq -e -r '.jobs.claude-review.steps[] | select(.id == "diff") | .run' "$WORKFLOW_FILE")"
repo="$work/repo"
git init -q -b main "$repo"
g() { git -C "$repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
echo base >"$repo/a" && g add a && g commit -qm b
g switch -qc pr
echo one >"$repo/p1" && g add p1 && g commit -qm p1 && p1="$(g rev-parse HEAD)"
echo two >"$repo/p2" && echo pr >"$repo/a" && g add p2 a && g commit -qm p2
g switch -q main && echo b2 >"$repo/b2" && echo main >"$repo/a" && g add b2 a && g commit -qm b2
g update-ref refs/remotes/origin/main main
g switch -q pr && { g merge -q main >/dev/null || true; } && echo both >"$repo/a" && g add a &&
    g commit -q --no-edit && merge="$(g rev-parse HEAD)"
g switch -q main && echo b3 >"$repo/b3" && g add b3 && g commit -qm b3
g update-ref refs/remotes/origin/main main && g switch -q pr
# The PR moves on to p3 after the event the step runs for.
echo three >"$repo/p3" && g add p3 && g commit -qm p3

# Runs the step with the scope after commit $1 and echoes the diff's path.
run_diff() {
    local dir="$work/diff-$2"
    mkdir -p "$dir"
    : >"$dir/out"
    (cd "$repo" && PAGES="$work/$2" GITHUB_REPOSITORY=org/repo PR=7 BASE_REF=main HEAD="$merge" \
        SINCE="$1" DIR="$dir" GITHUB_OUTPUT="$dir/out" \
        bash --noprofile --norc -eo pipefail -c "$diff_script") || fail "diff $2: the step failed"
    sed -n 's/^diff=//p' "$dir/out"
}

# Each file a diff names, by its head-side path.
files() { sed -n 's|^diff --git a/.* b/||p; s|^diff --cc ||p' "$1" | sort | tr '\n' ' '; }

new_case whole
got="$(files "$(run_diff "" whole)")"
[[ "$got" == "a p1 p2 " ]] || fail "diff whole: want the PR's a, p1 and p2, got: $got"

new_case since
since="$(run_diff "$p1" since)"
got="$(files "$since")"
[[ "$got" == "a a p2 " ]] || fail "diff since: want p2's a and p2 and the merge's resolution of a, got: $got"
grep -q "^commit $merge" "$since" || fail "diff since: the merge commit is not listed"
