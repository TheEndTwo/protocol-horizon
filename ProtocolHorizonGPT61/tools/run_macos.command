#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'run_macos.command: %s\n' "$*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)" \
  || fail 'cannot locate launcher directory.'
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)" \
  || fail 'cannot locate project directory.'
[[ -f "$PROJECT_DIR/project.godot" ]] \
  || fail "project.godot not found in '$PROJECT_DIR'."

validate_candidate() {
  local candidate="$1"
  local version_output

  if version_output="$("$candidate" --version 2>&1)" \
    && { [[ "$version_output" == 4.7.2.stable ]] || [[ "$version_output" == 4.7.2.stable.* ]]; }; then
    godot_bin="$candidate"
    return 0
  fi

  printf 'run_macos.command: ignoring incompatible Godot at %s (expected 4.7.2 stable; got: %s)\n' \
    "$candidate" "${version_output:-version check failed}" >&2
  return 1
}

godot_bin=''
if [[ -n "${GODOT_BIN:-}" ]]; then
  [[ -x "$GODOT_BIN" ]] \
    || fail "GODOT_BIN '$GODOT_BIN' is not executable; set it to the actual Godot 4.7.2 executable path."
  validate_candidate "$GODOT_BIN" \
    || fail 'GODOT_BIN must point to Godot 4.7.2 stable.'
else
  for name in godot godot4; do
    if command -v "$name" >/dev/null 2>&1; then
      candidate="$(command -v "$name")"
      if validate_candidate "$candidate"; then
        break
      fi
    fi
  done

  if [[ -z "$godot_bin" && "$(uname -s)" == Darwin ]] && command -v mdfind >/dev/null 2>&1; then
    while IFS= read -r app_bundle; do
      [[ -n "$app_bundle" && -d "$app_bundle" ]] || continue
      executable_name="$(defaults read "$app_bundle/Contents/Info" CFBundleExecutable 2>/dev/null || true)"
      [[ -n "$executable_name" ]] || continue
      candidate="$app_bundle/Contents/MacOS/$executable_name"
      [[ -x "$candidate" ]] || continue
      if validate_candidate "$candidate"; then
        break
      fi
    done < <(mdfind 'kMDItemCFBundleIdentifier == "org.godotengine.godot"' 2>/dev/null || true)
  fi
fi

[[ -n "$godot_bin" ]] \
  || fail 'Godot 4.7.2 stable was not found. Put godot/godot4 on PATH or pass its actual executable path with GODOT_BIN; no path is guessed or downloaded.'

exec "$godot_bin" --path "$PROJECT_DIR" "$@"
