#!/bin/bash
# install.sh — install, uninstall, or inspect the Puku CLI ↔ Herdr TUI adapter.
#
# Usage:
#   ./install.sh              install
#   ./install.sh --uninstall  remove everything the adapter installed
#   ./install.sh --status     show current state
#
# Install does three things:
#   1. Copies herdr-agent-state.sh to ~/.puku-cli/hooks/
#   2. Adds hook entries to ~/.puku-cli/settings.json (backup first)
#   3. Copies puku.toml to ~/.config/herdr/agent-detection/
#
# Uninstall removes only what install added. Other hooks, settings,
# and a user-modified puku.toml stay untouched.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PUKU_DIR="${HOME}/.puku-cli"
SETTINGS="${PUKU_DIR}/settings.json"
HOOK_DIR="${PUKU_DIR}/hooks"
HOOK_DEST="${HOOK_DIR}/herdr-agent-state.sh"
TOML_DEST="${HOME}/.config/herdr/agent-detection/puku.toml"
HOOK_MATCH="herdr-agent-state.sh"

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required" >&2
    exit 1
  fi
}

do_install() {
  require_jq
  mkdir -p "$HOOK_DIR" "$(dirname "$TOML_DEST")"

  # 1. Hook script.
  cp -f "${REPO_DIR}/herdr-agent-state.sh" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"

  # 2. settings.json — backup, then merge hook entries idempotently.
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
  else
    mkdir -p "$PUKU_DIR"
    echo '{}' > "$SETTINGS"
  fi

  jq --arg cmd "$HOOK_DEST" '
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

  # 3. Detection manifest (fallback when hooks are absent).
  cp -f "${REPO_DIR}/puku.toml" "$TOML_DEST"

  echo "Installed."
  echo "Run: herdr server reload-agent-manifests   (or restart Herdr)"
  echo "Verify: herdr agent explain <pane>"
}

do_uninstall() {
  require_jq

  # Remove only adapter hook entries from settings.json.
  if [ -f "$SETTINGS" ]; then
    cp "$SETTINGS" "${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
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
  fi

  # Remove hook script.
  [ -f "$HOOK_DEST" ] && rm -f "$HOOK_DEST"

  # Remove puku.toml only if it still matches ours; a user-customized
  # manifest stays untouched.
  if [ -f "$TOML_DEST" ]; then
    if cmp -s "$TOML_DEST" "${REPO_DIR}/puku.toml"; then
      rm -f "$TOML_DEST"
    else
      echo "note: puku.toml differs from the adapter copy — left in place"
    fi
  fi

  echo "Uninstalled."
  echo "Run: herdr server reload-agent-manifests   (or restart Herdr)"
}

do_status() {
  echo "Hook script:  $([ -f "$HOOK_DEST" ] && echo "yes ($HOOK_DEST)" || echo "no")"
  if [ -f "$TOML_DEST" ]; then
    cmp -s "$TOML_DEST" "${REPO_DIR}/puku.toml" \
      && echo "puku.toml:    yes (matches adapter)" \
      || echo "puku.toml:    yes (user-modified)"
  else
    echo "puku.toml:    no"
  fi
  if [ -f "$SETTINGS" ]; then
    N=$(jq -r --arg match "$HOOK_MATCH" '
      [.hooks // {} | .[] | .[] | select(.hooks // [] | any(.command | contains($match)))] | length' "$SETTINGS" 2>/dev/null || echo "?")
    echo "Hook entries: $N in $SETTINGS"
  else
    echo "Hook entries: no settings.json"
  fi
}

case "${1:-install}" in
  install) do_install ;;
  --uninstall|uninstall) do_uninstall ;;
  --status|status) do_status ;;
  *) echo "usage: $0 [--uninstall|--status]"; exit 2 ;;
esac
