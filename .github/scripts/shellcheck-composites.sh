#!/usr/bin/env bash
# actionlint rejects action.yml, so shell in a composite action is shellchecked
# here; the same check as pixtuoid's `just actionlint-composites`.
set -euo pipefail
shopt -s nullglob
actions=(.github/actions/*/action.y*ml) # GitHub accepts action.yaml too
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
checked=0
for action in "${actions[@]}"; do
    count="$(yq '[.runs.steps[] | select(has("run"))] | length' "$action")"
    ((count)) || continue # a pure `uses:` composite has no shell to check
    for i in $(seq 0 $((count - 1))); do
        shell="$(yq -r ".runs.steps | map(select(has(\"run\"))) | .[$i].shell" "$action")"
        script="$work/$(echo "$action" | tr /. __)-$i.$shell"
        { echo "#!/usr/bin/env $shell"; yq -r ".runs.steps | map(select(has(\"run\"))) | .[$i].run" "$action"; } >"$script"
        shellcheck -s "$shell" "$script" || { echo "  ^ from $action run step $i" >&2; exit 1; }
        checked=$((checked + 1))
    done
done
((checked > 0)) || { echo "error: no composite run: blocks were checked" >&2; exit 1; }
echo "$checked composite run: blocks shellchecked"
