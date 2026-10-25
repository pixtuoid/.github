#!/usr/bin/env bash
# The action's own shell against a stub rustup; run from the repo root.
set -euo pipefail

fail() {
    echo "setup-rust test: $*" >&2
    exit 1
}

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

rust_action=.github/actions/setup-rust/action.yml
rust_script="$(yq -e -r '.runs.steps[0].run' "$rust_action")" || fail "setup-rust has no run step"
rust_dir="$test_dir/rust"
mkdir -p "$rust_dir/bin"
# shellcheck disable=SC2016 # The stub reads its log path when it runs.
printf '%s\n' '#!/usr/bin/env bash' 'printf "rustup %s\n" "$*" >>"$FAKE_RUSTUP_LOG"' >"$rust_dir/bin/rustup"
chmod +x "$rust_dir/bin/rustup"
run_rust() {
    rm -f "$rust_dir/log"
    PATH="$rust_dir/bin:$PATH" FAKE_RUSTUP_LOG="$rust_dir/log" COMPONENTS="${1:-}" TARGETS="${2:-}" bash -c "$rust_script" >/dev/null 2>"$rust_dir/err"
}
rust_count() { grep -c -e "$1" "$rust_dir/log" || true; }
run_rust || fail "setup-rust failed with a healthy rustup"
[[ "$(rust_count '^rustup update')" == 1 ]] || fail "setup-rust did not update exactly once: $(<"$rust_dir/log")"
[[ "$(rust_count '^rustup toolchain install --profile minimal --no-self-update$')" == 1 ]] ||
    fail "setup-rust did not install the file's toolchain after the update: $(<"$rust_dir/log")"
[[ "$(rust_count '^rustup component\|^rustup target')" == 0 ]] || fail "setup-rust added components or targets nobody asked for: $(<"$rust_dir/log")"
run_rust "llvm-tools, rustfmt" "wasm32-unknown-unknown,aarch64-apple-darwin" || fail "setup-rust failed with extra components and targets"
[[ "$(rust_count '^rustup component add llvm-tools rustfmt$')" == 1 && "$(rust_count '^rustup target add wasm32-unknown-unknown aarch64-apple-darwin$')" == 1 ]] ||
    fail "setup-rust did not split the extra components and targets on commas: $(<"$rust_dir/log")"
