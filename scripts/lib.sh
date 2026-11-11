#!/bin/bash
# lib.sh — shared helpers for the Puku CLI ↔ Herdr TUI adapter.
# Sourced by install.sh and by tests. Not executed directly.

set -euo pipefail

# Repo root = parent of the directory containing this file.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PUKU_DIR="${PUKU_DIR:-${HOME}/.puku-cli}"
SETTINGS="${PUKU_DIR}/settings.json"
HOOK_DIR="${PUKU_DIR}/hooks"
HOOK_DEST="${HOOK_DIR}/herdr-agent-state.sh"
# shellcheck disable=SC2034  # consumed by install.sh
HOOK_SRC="${REPO_DIR}/bin/herdr-agent-state.sh"
TOML_DEST="${TOML_DEST:-${HOME}/.config/herdr/agent-detection/puku.toml}"
# shellcheck disable=SC2034  # consumed by install.sh
TOML_SRC="${REPO_DIR}/config/puku.toml"
HOOK_MATCH="herdr-agent-state.sh"

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
}

backup_settings() {
  [ -f "$SETTINGS" ] || return 0
  cp "$SETTINGS" "${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
}

# Merge the adapter's hook entries into settings.json (idempotent).
settings_install_hooks() {
  local cmd="$HOOK_DEST"
  mkdir -p "$PUKU_DIR"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  backup_settings
  jq --arg cmd "$cmd" '
    def withhook(ev; entry):
      .hooks[ev] = (((.hooks[ev] // []) | map(select(.hooks | any(.command == $cmd) | not))) + [entry]);
    .hooks //= {}
    | withhook("SessionStart";     {hooks: [{type: "command", command: $cmd}]})
    | withhook("UserPromptSubmit"; {hooks: [{type: "command", command: $cmd}]})
    | withhook("PreToolUse";       {matcher: ".*", hooks: [{type: "command", command: $cmd}]})
    | withhook("Stop";             {hooks: [{type: "command", command: $cmd}]})
    | withhook("PermissionRequest";{hooks: [{type: "command", command: $cmd}]})
    | withhook("StopFailure";      {hooks: [{type: "command", command: $cmd}]})
    | withhook("SessionEnd";       {hooks: [{type: "command", command: $cmd}]})
  ' "$SETTINGS" > "${SETTINGS}.tmp"
  mv "${SETTINGS}.tmp" "$SETTINGS"
}

# Remove only the adapter's hook entries; keep everything else.
settings_remove_hooks() {
  [ -f "$SETTINGS" ] || return 0
  backup_settings
  jq --arg match "$HOOK_MATCH" '
    if .hooks then
      .hooks |= (
        with_entries(.value |= map(select((.hooks // []) | any(.command | contains($match)) | not)))
        | with_entries(select(.value | length > 0))
      )
      | if .hooks == {} then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "${SETTINGS}.tmp"
  mv "${SETTINGS}.tmp" "$SETTINGS"
}

# Count adapter hook entries currently present in settings.json.
settings_hook_count() {
  [ -f "$SETTINGS" ] || { echo 0; return; }
  jq -r --arg match "$HOOK_MATCH" '
    [.hooks // {} | .[] | .[] | select(.hooks // [] | any(.command | contains($match)))] | length' \
    "$SETTINGS" 2>/dev/null || echo "?"
}
