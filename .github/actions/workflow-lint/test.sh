#!/usr/bin/env bash
# The action's zizmor policy and composite shellcheck against fixture repos,
# with the zizmor, shellcheck and yq on PATH; run from the repo root.
set -euo pipefail

fail() {
    echo "workflow-lint test: $*" >&2
    exit 1
}

action=.github/actions/workflow-lint/action.yml
step() { yq -e -r ".runs.steps[] | select(.name == \"$1\") | .run" "$action"; }
zizmor_script="$(step zizmor)"
shellcheck_script="$(step 'shellcheck composite actions')"
config="$PWD/.github/actions/workflow-lint/zizmor.yml"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A repo whose one workflow step is `uses: $2`, audited offline whatever token
# the shell holds (docs.zizmor.sh/usage/#operating-modes).
assert_zizmor() {
    local name="$1" uses="$2" expect="$3" repo="$work/zizmor-$1"
    mkdir -p "$repo/.github/workflows" "$repo/.github/actions/local"
    printf 'name: local\ndescription: local\nruns:\n  using: composite\n  steps:\n    - shell: bash\n      run: echo local\n' \
        >"$repo/.github/actions/local/action.yml"
    printf 'name: t\non: push\npermissions: {}\njobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: %s\n' \
        "$uses" >"$repo/.github/workflows/t.yml"
    if (cd "$repo" && ZIZMOR_OFFLINE=true CONFIG="$config" bash -eo pipefail -c "$zizmor_script") >"$work/$name.out" 2>&1; then
        [[ "$expect" == pass ]] || fail "zizmor passed $name"
    else
        [[ "$expect" == fail ]] || fail "zizmor failed $name: $(cat "$work/$name.out")"
    fi
}

assert_zizmor org-shared 'pixtuoid/.github/.github/actions/org-rules@main' pass
assert_zizmor hash-pinned 'foo/bar@0123456789abcdef0123456789abcdef01234567 # v1.0.0' pass
assert_zizmor tag-pinned 'foo/bar@v1' fail
assert_zizmor actions-tag 'actions/setup-node@v6' fail
assert_zizmor workspace-relative './.github/actions/local' pass

# A repo holding the composite actions given as `<dir>/<file>` and its body.
make_actions() {
    local repo="$work/sc-$1"
    shift
    mkdir -p "$repo"
    while (($#)); do
        mkdir -p "$repo/.github/actions/${1%/*}"
        printf '%s' "$2" >"$repo/.github/actions/$1"
        shift 2
    done
}
assert_shellcheck() {
    local name="$1" expect="$2"
    if (cd "$work/sc-$name" && bash -eo pipefail -c "$shellcheck_script") >"$work/sc-$name.out" 2>&1; then
        [[ "$expect" == pass ]] || fail "shellcheck passed $name"
    else
        [[ "$expect" == fail ]] || fail "shellcheck failed $name: $(cat "$work/sc-$name.out")"
    fi
}
composite() { printf 'name: a\ndescription: a\nruns:\n  using: composite\n  steps:\n%s' "$1"; }
# shellcheck disable=SC2016 # the fixtures' own shell, never expanded here
clean_run='    - shell: bash
      run: echo "$HOME"
' bad_run='    - shell: bash
      run: echo $HOME
'

make_actions clean a/action.yml "$(composite "$clean_run")"
assert_shellcheck clean pass
make_actions bad a/action.yml "$(composite "$bad_run")"
assert_shellcheck bad fail
make_actions second-step a/action.yml "$(composite "$clean_run$bad_run")"
assert_shellcheck second-step fail
make_actions second-action a/action.yml "$(composite "$clean_run")" b/action.yml "$(composite "$bad_run")"
assert_shellcheck second-action fail
make_actions yaml-extension a/action.yaml "$(composite "$bad_run")"
assert_shellcheck yaml-extension fail
make_actions uses-only a/action.yml "$(composite '    - uses: foo/bar@0123456789abcdef0123456789abcdef01234567
')"
assert_shellcheck uses-only pass
custom='shell: bash -e {0}' by_path='shell: /bin/bash -e {0}' dash='shell: dash {0}'
# Each with a clean twin, so a fail is shellcheck's finding, never a refused shell.
make_actions custom-shell a/action.yml "$(composite "${bad_run/shell: bash/$custom}")"
assert_shellcheck custom-shell fail
make_actions custom-shell-clean a/action.yml "$(composite "${clean_run/shell: bash/$custom}")"
assert_shellcheck custom-shell-clean pass
make_actions shell-path a/action.yml "$(composite "${bad_run/shell: bash/$by_path}")"
assert_shellcheck shell-path fail
make_actions shell-path-clean a/action.yml "$(composite "${clean_run/shell: bash/$by_path}")"
assert_shellcheck shell-path-clean pass
make_actions dash a/action.yml "$(composite "${bad_run/shell: bash/$dash}")"
assert_shellcheck dash fail
make_actions dash-clean a/action.yml "$(composite "${clean_run/shell: bash/$dash}")"
assert_shellcheck dash-clean pass
make_actions python a/action.yml "$(composite '    - shell: python
      run: print("ok")
')"
assert_shellcheck python pass
make_actions node a/action.yml $'name: a\ndescription: a\nruns:\n  using: node24\n  main: index.js\n'
assert_shellcheck node pass
make_actions none
assert_shellcheck none pass
