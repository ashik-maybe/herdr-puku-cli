#!/bin/bash
# lib.sh — shared helpers for the herdr-puku-cli adapter.
#
# Sourced by install.sh (and by tests). Not meant to be executed directly.
# Everything here is idempotent and safe to re-run: install merges, uninstall
# removes only what install added, status is read-only.

set -euo pipefail

# --- Repository root = parent of this script's directory. ----------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Install destinations. ------------------------------------------------------
# Overridable via env vars so tests can sandbox everything into a temp HOME
# without touching real state.
PUKU_DIR="${PUKU_DIR:-${HOME}/.puku-cli}"            # puku-cli user config dir
SETTINGS="${PUKU_DIR}/settings.json"                 # puku-cli user settings
HOOK_DIR="${PUKU_DIR}/hooks"                         # puku-cli hook scripts dir
HOOK_DEST="${HOOK_DIR}/herdr-agent-state.sh"         # where the hook lives
# shellcheck disable=SC2034  # consumed by install.sh
HOOK_SRC="${REPO_DIR}/bin/herdr-agent-state.sh"      # hook as shipped by us
HOOK_MATCH="herdr-agent-state.sh"                    # identifies our hook entries

# Legacy cleanup destination (we no longer ship a screen manifest). Kept only
# so `install.sh --uninstall` can warn about a leftover from an old install.
TOML_DEST="${TOML_DEST:-${HOME}/.config/herdr/agent-detection/puku.toml}"

log() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
}

backup_settings() {
  # puku-cli's settings.json also carries permissions, MCP, etc. — we never
  # touch those, but we always snapshot before any write so recovery is easy.
  [ -f "$SETTINGS" ] || return 0
  cp "$SETTINGS" "${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
}

# --- Merge our hook entries into puku settings.json (idempotent). --------------
# puku-cli runs hooks from a top-level "hooks" object keyed by event name.
# Each event holds an array of matcher entries, each holding an array of
# commands. We add exactly one entry per event, and remove our older entry
# (matched by $cmd) before adding — that is what makes re-install idempotent.
# Other people's hooks (different commands) are preserved untouched.
settings_install_hooks() {
  local cmd="$HOOK_DEST"
  mkdir -p "$PUKU_DIR"
  # puku-cli silently ignores settings.json on JSON parse error, so an empty
  # starting file must at least be valid JSON.
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  backup_settings
  jq --arg cmd "$cmd" '
    def withhook(ev; entry):
      .hooks[ev] = (((.hooks[ev] // []) | map(select(.hooks | any(.command == $cmd) | not))) + [entry]);
    .hooks //= {}
    # Non-tool events need no matcher (nothing to match against).
    | withhook("SessionStart";     {hooks: [{type: "command", command: $cmd}]})
    | withhook("UserPromptSubmit"; {hooks: [{type: "command", command: $cmd}]})
    # PreToolUse is matched against the tool *name*; ".*" = every tool.
    | withhook("PreToolUse";       {matcher: ".*", hooks: [{type: "command", command: $cmd}]})
    | withhook("Stop";             {hooks: [{type: "command", command: $cmd}]})
    | withhook("SessionEnd";       {hooks: [{type: "command", command: $cmd}]})
    | withhook("PermissionRequest";{hooks: [{type: "command", command: $cmd}]})
    | withhook("StopFailure";      {hooks: [{type: "command", command: $cmd}]})
    | withhook("Elicitation";      {hooks: [{type: "command", command: $cmd}]})
    # Notification is matched against notification_type; the adapter reports
    # blocked only for permission_prompt/elicitation_dialog (see hook script).
    | withhook("Notification";     {hooks: [{type: "command", command: $cmd}]})
  ' "$SETTINGS" > "${SETTINGS}.tmp"
  mv "${SETTINGS}.tmp" "$SETTINGS"
}

# --- Remove only our hook entries from settings.json. ---------------------------
# Matching is deliberately loose (contains $HOOK_MATCH) so stale entries
# pointing at older install paths still get cleaned up. Everything else —
# other hooks, other keys, unrelated events — is left exactly as found.
settings_remove_hooks() {
  [ -f "$SETTINGS" ] || return 0
  backup_settings
  jq --arg match "$HOOK_MATCH" '
    if .hooks then
      .hooks |= (
        with_entries(.value |= map(select((.hooks // []) | any(.command | contains($match)) | not)))
        | with_entries(select(.value | length > 0))   # drop events left empty
      )
      | if .hooks == {} then del(.hooks) else . end   # drop empty hooks object
    else . end
  ' "$SETTINGS" > "${SETTINGS}.tmp"
  mv "${SETTINGS}.tmp" "$SETTINGS"
}

# --- Count our hook entries currently registered (used by --status). -----------
settings_hook_count() {
  [ -f "$SETTINGS" ] || { echo 0; return; }
  jq -r --arg match "$HOOK_MATCH" '
    [.hooks // {} | .[] | .[] | select(.hooks // [] | any(.command | contains($match)))] | length' \
    "$SETTINGS" 2>/dev/null || echo "?"
}

# --- Legacy: warn about the puku.toml screen manifest old installs left behind.
# Current versions do not ship a detection manifest (Herdr cannot identify an
# unknown puku process; overrides only patch known agents). We never delete a
# user file we cannot freshly compare against our own copy, so just say it.
legacy_manifest_note() {
  if [ -f "$TOML_DEST" ]; then
    log "note: $TOML_DEST was left by an older adapter version and is now inert; delete it manually if you do not need it"
  fi
}
