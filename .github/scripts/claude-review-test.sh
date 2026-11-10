#!/usr/bin/env bash
# claude-review.yml's scope and diff steps against fixtures, and the JSON its
# claude_args carries; run from the repo root.
set -euo pipefail

fail() {
    echo "claude-review test: $*" >&2
    exit 1
}

WORKFLOW_FILE=.github/workflows/claude-review.yml
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

# Runs the step over the pages a case wrote and sets $dir, $comments,
# $recheck and $verdicts.
run_step() {
    local out="$work/$1.out"
    : >"$out"
    PAGES="$PAGES" GITHUB_REPOSITORY=org/repo PR=7 RUNNER_TEMP="$work/$1.tmp" GITHUB_OUTPUT="$out" \
        VERDICTS="$verdicts_jq" COMMENT="$comment_jq" RECHECK="$recheck_jq" \
        bash --noprofile --norc -eo pipefail -c "$script" || fail "$1: the step failed"
    dir="$(sed -n 's/^dir=//p' "$out")"
    comments="$(sed -n 's/^comments=//p' "$out")"
    recheck="$(sed -n 's/^recheck=//p' "$out")"
    verdicts="$dir/verdicts.jsonl"
    [[ -f "$comments" ]] || fail "$1: no comments file at '$comments'"
    [[ -f "$recheck" ]] || fail "$1: no recheck file at '$recheck'"
    [[ -f "$verdicts" ]] || fail "$1: no verdicts file at '$verdicts'"
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

# The verdicts VERDICTS kept, oldest first, as `<commit>/<C or I>/<ids>`: the
# commit's number, complete or incomplete, and the ids listed as judged.
assert_verdicts() {
    local name="$1" want="$2" got
    run_step "$name"
    got="$(jq -r -s 'map("\(.commit_id | tonumber)/\(if .incomplete then "I" else "C" end)/\(.read | join(","))") | join(" ")' "$verdicts")"
    [[ "$got" == "$want" ]] || fail "$name: verdicts '$got', want '$want'"
}

bot='github-actions[bot]'

new_case first
{ commit 1; commit 2; } | page commits 1
assert_verdicts first ""

# The MCP tool's one page was what hid pixtuoid#1648's newest reviews.
new_case newest-on-page-2
commit 1 | page commits 1
{ commit 2; commit 3; } | page commits 2
review "$bot" 1 'Blocking: 0' | page reviews 1
review "$bot" 2 $'Blocking: 1\n\n**Verdict:** one blocking finding' | page reviews 2
assert_verdicts newest-on-page-2 "1/C/ 2/C/"

# Only the bot's reviews whose first line is a verdict count; a list-less
# incomplete one is kept, since it can only keep units in scope.
new_case no-verdict
{ commit 1; commit 2; commit 3; commit 4; commit 5; } | page commits 1
{
    review "$bot" 1 'Blocking: 0'
    review "$bot" 2 ''
    review "$bot" 3 $'**Verdict:** fine\nBlocking: 0'
    review "$bot" 4 $'Blocking: incomplete\n\n**Verdict:** read nothing'
    review someone 5 'Blocking: 0'
} | page reviews 1
assert_verdicts no-verdict "1/C/ 4/I/"

# Step 3's `Read:` list, as VERDICTS parses it: each unit line's id, a twin
# group's included, past blank lines; a sub-bullet, prose or an item line
# is no id, so the unit it stands for stays in scope.
new_case incomplete-listed
{ commit 1; commit 2; } | page commits 1
{
    review "$bot" 1 'Blocking: 0'
    review "$bot" 2 $'Blocking: incomplete\n\nRead:\n- 0123456789ab src/x.rs:+40,3\n \t\n- 0123456789ac.2 b.rs:+1,1,+9,1\n  - 0123456789ad a.rs:+12,1\n- a.rs: fn foo\nthen prose\n'
} | page reviews 1
assert_verdicts incomplete-listed "1/C/ 2/I/0123456789ab,0123456789ac.2"

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
# then moves on to b3, and the checkout past the event's head to p3. p2 also
# marks the PR's files -diff, which must not hide their hunks.
diff_script="$(yq -e -r '.jobs.claude-review.steps[] | select(.id == "diff") | .run' "$WORKFLOW_FILE")"
units_py="$(yq -e -r '.jobs.claude-review.steps[] | select(.id == "diff") | .env.UNITS' "$WORKFLOW_FILE")"
g() { git -C "$repo" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
repo="$work/repo"
git init -q -b main "$repo"
echo base >"$repo/a" && g add a && g commit -qm b
g switch -qc pr
echo one >"$repo/p1" && g add p1 && g commit -qm p1 && p1="$(g rev-parse HEAD)"
echo two >"$repo/p2" && echo pr >"$repo/a" && echo 'p* -diff' >"$repo/.gitattributes" &&
    g add p2 a .gitattributes && g commit -qm p2
g switch -q main && echo b2 >"$repo/b2" && echo main >"$repo/a" && g add b2 a && g commit -qm b2
g update-ref refs/remotes/origin/main main
g switch -q pr && { g merge -q main >/dev/null || true; } && echo both >"$repo/a" && g add a &&
    g commit -q --no-edit && merge="$(g rev-parse HEAD)"
g switch -q main && echo b3 >"$repo/b3" && g add b3 && g commit -qm b3
g update-ref refs/remotes/origin/main main && g switch -q pr
# The PR moves on to p3 after the event the step runs for.
echo three >"$repo/p3" && g add p3 && g commit -qm p3

# A verdict as VERDICTS writes it: verdict <commit> <incomplete> [judged id…].
verdict() {
    local c="$1" inc="$2"
    shift 2
    jq -nc --arg c "$c" --argjson inc "$inc" '{commit_id: $c, submitted_at: "", incomplete: $inc, read: $ARGS.positional}' --args "$@"
}
# Runs the step as run $1 at head $2 in $repo, over the verdicts on stdin;
# units_of and whole_of read its outputs.
run_diff() {
    local dir="$work/diff-$1"
    mkdir -p "$dir"
    cat >"$dir/verdicts.jsonl"
    g rev-list "origin/main..$2" >"$dir/commits"
    run_diff_in "$1" "$2" "$dir"
}
# The same over the scope step's own directory $3, whose files it reads.
run_diff_in() {
    : >"$work/diff-$1.out"
    (cd "$repo" && BASE_REF=main HEAD="$2" DIR="$3" UNITS="$units_py" GITHUB_OUTPUT="$work/diff-$1.out" \
        bash --noprofile --norc -eo pipefail -c "$diff_script") || fail "diff $1: the step failed"
}
units_of() { sed -n 's/^units=//p' "$work/diff-$1.out"; }
whole_of() { sed -n 's/^whole=//p' "$work/diff-$1.out"; }
# The paths the scope of run $1 names, sorted.
paths() { sed -E 's/^- [^ ]+ (.*):[^:]*$/\1/' "$(units_of "$1")" | sort | tr '\n' ' '; }
# The ids of the units in file $2 in the scope of run $1, one per line.
ids_of() { awk -v p="$2" 'substr($0, index($0, $3)) ~ "^" p ":" { print $2 }' "$(units_of "$1")"; }

run_diff whole "$merge" </dev/null
[[ "$(paths whole)" == ".gitattributes a p1 p2 " ]] || fail "diff whole: with no verdict every unit is in scope, got: $(paths whole)"
grep -q ' p1:+1,1$' "$(units_of whole)" || fail "diff whole: the PR's own .gitattributes turned p1's hunk into a file unit"
grep -qx '+one' "$(whole_of whole)" || fail "diff whole: the PR's own .gitattributes hid p1's hunk"
p1_id="$(ids_of whole p1)"

# A unit the merge of main left alone keeps its id, so a complete review of p1
# judged it.
verdict "$p1" false | run_diff complete "$merge"
[[ "$(paths complete)" == ".gitattributes a p2 " ]] || fail "diff complete: want the units new since p1, got: $(paths complete)"
grep -qx '+one' "$(whole_of complete)" || fail "diff complete: the whole diff lacks p1's hunk"

# An incomplete review takes out only what it lists as judged: a unit it left
# off, or an id it was never given, keeps p1 in scope.
verdict "$p1" true | run_diff left-off "$merge"
[[ "$(paths left-off)" == ".gitattributes a p1 p2 " ]] || fail "diff left-off: want p1 kept, got: $(paths left-off)"
verdict "$p1" true 0123456789ab | run_diff invented "$merge"
[[ "$(paths invented)" == ".gitattributes a p1 p2 " ]] || fail "diff invented: want p1 kept, got: $(paths invented)"
verdict "$p1" true "$p1_id" | run_diff listed "$merge"
[[ "$(paths listed)" == ".gitattributes a p2 " ]] || fail "diff listed: want p1 judged, got: $(paths listed)"

# Reruns at one head shrink the scope by what each lists, and a verdict on a
# commit a force-push dropped is skipped.
a_id="$(ids_of whole a)" p2_id="$(ids_of whole p2)"
{
    verdict "$merge" true "$a_id" "$p1_id"
    verdict 0000000000000000000000000000000000000009 true "$p2_id"
    verdict "$merge" true "$p2_id"
} | run_diff reruns "$merge"
[[ "$(paths reruns)" == ".gitattributes " ]] || fail "diff reruns: want only .gitattributes left, got: $(paths reruns)"

# The format step 3 asks for, a line the step wrote, parses back to its id.
new_case read-back
commit 1 | page commits 1
review "$bot" 1 "$(printf 'Blocking: incomplete\n\nRead:\n%s' "$(grep ' p1:' "$(units_of whole)")")" | page reviews 1
assert_verdicts read-back "1/I/$p1_id"

# The scope step's files, read by the diff step as they are: an incomplete
# review of p1 that judged p1's unit takes it out, and one that listed
# nothing keeps it.
new_case handoff
for c in $(g rev-list --reverse "origin/main..$merge"); do jq -nc --arg sha "$c" '{sha: $sha}'; done | page commits 1
{
    jq -nc --arg by "$bot" --arg sha "$p1" --arg body "$(printf 'Blocking: incomplete\n\nRead:\n%s' "$(grep ' p1:' "$(units_of whole)")")" \
        '{user: {login: $by}, commit_id: $sha, body: $body, submitted_at: "2026-01-01T00:01:00Z"}'
} | page reviews 1
run_step handoff
run_diff_in handoff "$merge" "$dir"
[[ "$(paths handoff)" == ".gitattributes a p2 " ]] || fail "diff handoff: want p1 judged through the scope step's files, got: $(paths handoff)"
new_case handoff-incomplete
for c in $(g rev-list --reverse "origin/main..$merge"); do jq -nc --arg sha "$c" '{sha: $sha}'; done | page commits 1
jq -nc --arg by "$bot" --arg sha "$p1" '{user: {login: $by}, commit_id: $sha, body: "Blocking: incomplete", submitted_at: "2026-01-01T00:01:00Z"}' | page reviews 1
run_step handoff-incomplete
run_diff_in handoff-incomplete "$merge" "$dir"
[[ "$(paths handoff-incomplete)" == ".gitattributes a p1 p2 " ]] || fail "diff handoff-incomplete: an incomplete review that listed nothing took p1 out"

# A push that shifts a hunk's lines keeps its id when its context holds, and an
# edit next to a hunk changes it; twins are one unit whose id counts them, so
# one more twin re-reads the group; a mode change keys the file's first hunk;
# a path with " b/" in it keeps its name.
repo="$work/shift"
git init -q -b main "$repo"
seq 1 40 | sed 's/^/l/' >"$repo/s"
# Three identical blocks with identical blank lines around them, so their
# hunks match context and all.
for _ in 1 2 3; do printf '\n\n\n\nfn a() {\n    x\n}\n\n\n\n\n'; done >"$repo/w"
# The same change in two different items is two units, not twins.
printf 'fn a() {\n    x\n}\n\n\n\n\n\n\n\nfn b() {\n    x\n}\n' >"$repo/v"
mkdir -p "$repo/d b" && echo old >"$repo/d b/c" && echo old >"$repo/x.sh"
g add s w v "d b/c" x.sh && g commit -qm b && g update-ref refs/remotes/origin/main main
g switch -qc pr
sed -i.bak -e 's/^l10$/x10/' -e 's/^l30$/x30/' "$repo/s" && rm "$repo/s.bak"
awk '/^    x$/ && n < 2 { n++; print "    y"; next } { print }' "$repo/w" >"$repo/w.new" && mv "$repo/w.new" "$repo/w"
sed -i.bak 's/^    x$/    y/' "$repo/v" && rm "$repo/v.bak"
echo new >"$repo/d b/c" && echo new >"$repo/x.sh"
g add s w v "d b/c" x.sh && g commit -qm one && one="$(g rev-parse HEAD)"
run_diff one "$one" </dev/null
[[ "$(grep -c ' w:' "$(units_of one)")" == 1 ]] || fail "diff one: twins split into units"
[[ "$(ids_of one w)" == *.2 ]] || fail "diff one: want the two twins as one unit counting them, got '$(ids_of one w)'"
[[ "$(ids_of one v | wc -l | tr -d ' ')" == 2 && "$(ids_of one v)" != *.* ]] ||
    fail "diff one: the same change in two items must be two units, got '$(ids_of one v)'"
grep -q ' d b/c:+1,1$' "$(units_of one)" || fail "diff one: a path with \" b/\" lost its name"
x30="$(ids_of one s | tail -n 1)"
{ printf 't1\nt2\nt3\n'; cat "$repo/s"; } >"$repo/s.new" && mv "$repo/s.new" "$repo/s"
awk '/^    x$/ { print "    y"; next } { print }' "$repo/w" >"$repo/w.new" && mv "$repo/w.new" "$repo/w"
chmod +x "$repo/x.sh"
g add s w x.sh && g commit -qm two && two="$(g rev-parse HEAD)"
verdict "$one" false | run_diff two "$two"
grep -q " $x30 " "$(units_of two)" && fail "diff two: a shifted hunk whose context held came back"
grep -q ' s:+1,' "$(units_of two)" || fail "diff two: the new hunk at the top of s is not in scope"
[[ "$(ids_of two w)" == *.3 ]] || fail "diff two: one more twin must re-read the group, got '$(ids_of two w)'"
grep -q ' x.sh:' "$(units_of two)" || fail "diff two: a mode change left the file's unit out of scope"
grep -q ' v:' "$(units_of two)" && fail "diff two: an untouched file came back"

# claude-code-action splits claude_args like a shell before the CLI reads
# --settings and --agents as JSON, and review.yml runs this workflow from main,
# so an apostrophe ending a quote early (.github#28) breaks every repo's review
# once it lands. shlex stands in for the action's shell-quote, without parity
# on what our args don't use, such as $ expansion or # comments.
action='.jobs.claude-review.steps[] | select(.uses // "" | test("^anthropics/claude-code-action@"))'
claude_args="$(yq -e -r "$action | .with.claude_args" "$WORKFLOW_FILE")"
prompt="$(yq -e -r "$action | .with.prompt" "$WORKFLOW_FILE")"
CLAUDE_ARGS="$claude_args" PROMPT="$prompt" python3 -I -c '
import json, os, shlex
args = shlex.split(os.environ["CLAUDE_ARGS"])
json.loads(args[args.index("--settings") + 1])
agents = json.loads(args[args.index("--agents") + 1])
for agent in ("correctness-reviewer", "design-reviewer", "verifier"):
    assert agent in os.environ["PROMPT"], f"the prompt names no {agent}"
    assert isinstance(agents[agent]["tools"], list), f"--agents gives {agent} no tools"
' || fail "claude_args: --settings and --agents must split into JSON that gives each listed agent its tools"

# Step 3's `Read:` format is what the model writes; read-back holds VERDICTS
# to a line the diff step wrote, and this holds the prompt to the same format,
# so a reworded prompt can't leave every unit in scope forever.
# shellcheck disable=SC2016 # the backticks are the prompt's own, not expansions
[[ "$prompt" == *'an incomplete one ends with a `Read:` line, then the `- <id> <path>:<range>` line of each scope unit'* ]] ||
    fail "prompt: step 3 no longer asks for the \`Read:\` format VERDICTS parses"
