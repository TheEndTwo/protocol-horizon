#!/usr/bin/env bash
set -euo pipefail
project="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$project/tools/run_macos.command"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/horizon-tests.XXXXXX")"
export HORIZON_TEST_ISOLATED=1
export XDG_DATA_HOME="$test_root/data"
# Disposable user-data is separate from every installed game profile.
if [[ "$(uname -s)" == Darwin ]]; then
  printf 'On macOS run isolated tests in a disposable OS user; XDG_DATA_HOME is Linux-specific.\n' >&2
  exit 2
fi
run() {
  local log="$test_root/$(date +%s)-$RANDOM.log"
  if ! bash "$launcher" "$@" >"$log" 2>&1; then
    cat "$log"
    return 1
  fi
  cat "$log"
  if grep -E 'SCRIPT ERROR|^ERROR:|FAIL:' "$log"; then
    return 1
  fi
}
run --headless --editor --import
for test in stage0_test economy_test progression_test sites_test meta_test events_test research_runtime_test balance_test; do
  run --headless --script "res://tests/$test.gd"
done
export XDG_DATA_HOME="$test_root/session"
run --headless --script res://tests/earth_session_test.gd
run --headless --script res://tests/earth_session_test.gd -- --reload
export XDG_DATA_HOME="$test_root/ui"
run --headless --script res://tests/earth_ui_test.gd
export XDG_DATA_HOME="$test_root/settings-regression"
run --headless --script res://tests/stage1_test.gd
run --headless --script res://tests/stage1_test.gd -- --reload
export XDG_DATA_HOME="$test_root/save-cases"
run --headless --script res://tests/save_service_test.gd
printf '\nGame tests passed. Disposable test evidence: %s\n' "$test_root"
