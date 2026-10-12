#!/usr/bin/env bash
# The action's own shell against a stub rustup; run from the repo root.
set -euo pipefail

fail() {
    echo "setup-rust test: $*" >&2
    exit 1
}

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

# ── setup-rust: rustup's release-day manifest race retries under the action's
# own bound, and any other failure exits at once with rustup's status.
rust_action=.github/actions/setup-rust/action.yml
rust_script="$(yq -e -r '.runs.steps[0].run' "$rust_action")" || fail "setup-rust has no run step"
rust_attempts="$(yq -e -r '.runs.steps[0].env.UPDATE_ATTEMPTS' "$rust_action")" || fail "setup-rust sets no UPDATE_ATTEMPTS"
((rust_attempts > 1)) || fail "setup-rust allows $rust_attempts attempt(s), so nothing retries"
rust_dir="$test_dir/rust"
mkdir -p "$rust_dir/bin"
# Fails the first FAKE_RUSTUP_FAILS `update` calls with FAKE_RUSTUP_MESSAGE on stderr and status 7.
# shellcheck disable=SC2016 # The stub reads its fixtures when it runs.
printf '%s\n' '#!/usr/bin/env bash' 'printf "rustup %s\n" "$*" >>"$FAKE_RUSTUP_LOG"' \
    '[[ "$1" == update ]] || exit 0' \
    'n=$(($(cat "$FAKE_RUSTUP_LOG.n" 2>/dev/null || echo 0) + 1)); echo $n >"$FAKE_RUSTUP_LOG.n"' \
    '((n > FAKE_RUSTUP_FAILS)) || { printf "%s\n" "$FAKE_RUSTUP_MESSAGE" >&2; exit 7; }' >"$rust_dir/bin/rustup"
chmod +x "$rust_dir/bin/rustup"
race_message='warning: component manifest checksum failed for x
info: this is likely due to an ongoing update of the official release server, please try again later'
run_rust() {
    rm -f "$rust_dir/log" "$rust_dir/log.n"
    PATH="$rust_dir/bin:$PATH" FAKE_RUSTUP_LOG="$rust_dir/log" FAKE_RUSTUP_FAILS="$1" FAKE_RUSTUP_MESSAGE="$2" COMPONENTS="${3:-}" TARGETS="${4:-}" \
        UPDATE_ATTEMPTS="$rust_attempts" UPDATE_RETRY_SECONDS=0 bash -c "$rust_script" >/dev/null 2>"$rust_dir/err"
}
rust_count() { grep -c -e "$1" "$rust_dir/log" || true; }
run_rust 0 "" || fail "setup-rust failed with a healthy rustup"
# An empty list expands unbound under bash 3.2, which warns and still exits 0.
[[ ! -s "$rust_dir/err" ]] || fail "setup-rust wrote to stderr on a healthy run: $(<"$rust_dir/err")"
[[ "$(rust_count '^rustup update')" == 1 ]] || fail "setup-rust updated more than once: $(<"$rust_dir/log")"
[[ "$(rust_count '^rustup toolchain install --profile minimal --no-self-update$')" == 1 ]] ||
    fail "setup-rust did not install the file's toolchain after the update: $(<"$rust_dir/log")"
[[ "$(rust_count '^rustup component\|^rustup target')" == 0 ]] || fail "setup-rust added components or targets nobody asked for: $(<"$rust_dir/log")"
run_rust $((rust_attempts - 1)) "$race_message" || fail "setup-rust did not recover from the manifest race on its last attempt"
[[ "$(rust_count '^rustup update')" == "$rust_attempts" ]] || fail "setup-rust did not retry the manifest race: $(<"$rust_dir/log")"
status=0
run_rust "$rust_attempts" "$race_message" || status=$?
[[ "$status" == 7 ]] || fail "setup-rust exited $status after the race outlasted its attempts, not rustup's status"
[[ "$(rust_count '^rustup update')" == "$rust_attempts" && "$(rust_count 'toolchain install')" == 0 ]] ||
    fail "setup-rust went on after the race outlasted its attempts: $(<"$rust_dir/log")"
for message in "error: could not download file: network down" "warning: component manifest checksum failed for x" \
    "info: this is likely due to an ongoing update of the official release server"; do
    status=0
    run_rust "$rust_attempts" "$message" || status=$?
    [[ "$status" == 7 ]] || fail "setup-rust exited $status on \"$message\", not rustup's status"
    [[ "$(rust_count '^rustup update')" == 1 && "$(rust_count 'toolchain install')" == 0 ]] ||
        fail "setup-rust retried or went on after \"$message\": $(<"$rust_dir/log")"
done
run_rust 0 "" "llvm-tools, rustfmt" "wasm32-unknown-unknown,aarch64-apple-darwin" || fail "setup-rust failed with extra components and targets"
[[ "$(rust_count '^rustup component add llvm-tools rustfmt$')" == 1 && "$(rust_count '^rustup target add wasm32-unknown-unknown aarch64-apple-darwin$')" == 1 ]] ||
    fail "setup-rust did not split the extra components and targets on commas: $(<"$rust_dir/log")"
