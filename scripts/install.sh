#!/bin/bash
# install.sh — install, uninstall, or inspect the herdr-puku-cli adapter.
#
# Usage:
#   install.sh              install
#   install.sh --uninstall  remove everything the adapter installed
#   install.sh --status     show current state
#
# PURPOSE
#   One command wires puku-cli up to Herdr: it copies the hook into
#   ~/.puku-cli/hooks/, registers it in ~/.puku-cli/settings.json (merged,
#   never clobbering existing config), and is equally usable standalone and
#   through the herdr plugin actions (see herdr-plugin.toml).
#
# GUARANTEES
#   * idempotent        — re-running install never duplicates hook entries
#   * backs up          — settings.json is copied to settings.json.bak.<ts>
#   * minimal footprint — uninstall removes only what install added
#   * no surprises      — a user-edited or foreign settings.json keeps its
#                         contents; only our entries come and go
#
# DESTINATIONS can be overridden via env (used by tests):
#   PUKU_DIR   (default ~/.puku-cli)   — puku-cli user directory
#   TOML_DEST  (default ~/.config/herdr/agent-detection/puku.toml) — legacy

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "${REPO_DIR}/scripts/lib.sh"

do_install() {
  require_jq
  mkdir -p "$HOOK_DIR"

  # 1. Hook script — copied (not symlinked) so plugin updates/reinstalls
  #    can't invalidate the path puku-cli will execute.
  cp -f "$HOOK_SRC" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"

  # 2. puku-cli settings.json — merge our hook entries, keep everything else.
  settings_install_hooks

  log "Installed herdr-puku-cli."
  log "Restart puku-cli, then verify with: herdr agent list"
  log "(or: herdr agent explain <pane> --json)"
}

do_uninstall() {
  require_jq

  # 1. Remove our hook entries from settings.json (backs up first).
  settings_remove_hooks

  # 2. Remove the hook script itself.
  [ -f "$HOOK_DEST" ] && rm -f "$HOOK_DEST"

  # 3. Warn about a leftover detection manifest from older versions.
  legacy_manifest_note

  log "Uninstalled herdr-puku-cli."
}

do_status() {
  echo "Hook script:  $([ -f "$HOOK_DEST" ] && echo "yes ($HOOK_DEST)" || echo "no")"
  echo "Hook entries: $(settings_hook_count) in $SETTINGS (8 expected)"
  legacy_manifest_note
}

case "${1:-install}" in
  install) do_install ;;
  --uninstall|uninstall) do_uninstall ;;
  --status|status) do_status ;;
  *) echo "usage: $0 [--uninstall|--status]" >&2; exit 2 ;;
esac
