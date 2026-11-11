#!/bin/bash
# install.sh — install, uninstall, or inspect the Puku CLI ↔ Herdr TUI adapter.
#
# Usage:
#   install.sh              install
#   install.sh --uninstall  remove everything the adapter installed
#   install.sh --status     show current state
#
# Used both standalone (./scripts/install.sh) and by the herdr plugin actions
# declared in herdr-plugin.toml. Override destinations via PUKU_DIR and
# TOML_DEST env vars (used by tests).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "${REPO_DIR}/scripts/lib.sh"

do_install() {
  require_jq
  mkdir -p "$HOOK_DIR" "$(dirname "$TOML_DEST")"

  # 1. Hook script.
  cp -f "$HOOK_SRC" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"

  # 2. settings.json — backup, then merge hook entries idempotently.
  settings_install_hooks

  # 3. Detection manifest (fallback when hooks are absent).
  cp -f "$TOML_SRC" "$TOML_DEST"

  log "Installed."
  log "Run: herdr server reload-agent-manifests   (or restart Herdr)"
  log "Verify: herdr agent explain <pane>"
}

do_uninstall() {
  require_jq
  settings_remove_hooks
  [ -f "$HOOK_DEST" ] && rm -f "$HOOK_DEST"

  # Remove puku.toml only if it still matches ours; a user-customized
  # manifest stays untouched.
  if [ -f "$TOML_DEST" ]; then
    if cmp -s "$TOML_DEST" "$TOML_SRC"; then
      rm -f "$TOML_DEST"
    else
      log "note: puku.toml differs from the adapter copy — left in place"
    fi
  fi

  log "Uninstalled."
  log "Run: herdr server reload-agent-manifests   (or restart Herdr)"
}

do_status() {
  echo "Hook script:  $([ -f "$HOOK_DEST" ] && echo "yes ($HOOK_DEST)" || echo "no")"
  if [ -f "$TOML_DEST" ]; then
    cmp -s "$TOML_DEST" "$TOML_SRC" \
      && echo "puku.toml:    yes (matches adapter)" \
      || echo "puku.toml:    yes (user-modified)"
  else
    echo "puku.toml:    no"
  fi
  echo "Hook entries: $(settings_hook_count) in $SETTINGS"
}

case "${1:-install}" in
  install) do_install ;;
  --uninstall|uninstall) do_uninstall ;;
  --status|status) do_status ;;
  *) echo "usage: $0 [--uninstall|--status]" >&2; exit 2 ;;
esac
