#!/bin/bash
# tests/run.sh — plain bash test runner for the adapter. No external deps beyond jq.
# Uses a temporary HOME so real ~/.puku-cli and ~/.config/herdr stay untouched.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK"
export PUKU_DIR="$WORK/.puku-cli"
export TOML_DEST="$WORK/.config/herdr/agent-detection/puku.toml"

PASS=0 FAIL=0

ok()   { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
check() { # check <name> <command...>
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}

# --- hook: no-op outside Herdr ---
out="$(printf '{"hook_event_name":"Stop"}' | bash "$REPO_DIR/bin/herdr-agent-state.sh"; echo "exit=$?")"
[ "$out" = "exit=0" ] && ok "hook exits 0 outside herdr" || bad "hook exits 0 outside herdr"

# --- hook: reports state inside herdr (stub herdr on PATH) ---
STUB_BIN="$WORK/stub-bin"; mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/herdr" <<'EOF'
#!/bin/bash
echo "$@" >> "$STUB_LOG"
EOF
chmod +x "$STUB_BIN/herdr"
export STUB_LOG="$WORK/herdr.log"
: > "$STUB_LOG"
echo '{"hook_event_name":"PreToolUse"}' | PATH="$STUB_BIN:$PATH" HERDR_ENV=1 HERDR_PANE_ID=p1 bash "$REPO_DIR/bin/herdr-agent-state.sh"
sleep 0.2  # hook is fire-and-forget
check "hook reports working on PreToolUse" grep -q -- "--state working" "$STUB_LOG"
echo '{"hook_event_name":"PermissionRequest"}' | PATH="$STUB_BIN:$PATH" HERDR_ENV=1 HERDR_PANE_ID=p1 bash "$REPO_DIR/bin/herdr-agent-state.sh"
sleep 0.2
check "hook reports blocked on PermissionRequest" grep -q -- "--state blocked" "$STUB_LOG"
echo '{"hook_event_name":"Stop"}' | PATH="$STUB_BIN:$PATH" HERDR_ENV=1 HERDR_PANE_ID=p1 bash "$REPO_DIR/bin/herdr-agent-state.sh"
sleep 0.2
check "hook reports idle on Stop" grep -q -- "--state idle" "$STUB_LOG"

# --- install ---
check "install runs" bash "$REPO_DIR/scripts/install.sh"
check "hook copied" test -x "$PUKU_DIR/hooks/herdr-agent-state.sh"
check "puku.toml copied" test -f "$TOML_DEST"
N="$(jq '[.hooks | to_entries[] | .value[]] | length' "$PUKU_DIR/settings.json")"
[ "$N" = "7" ] && ok "7 hook entries installed" || bad "7 hook entries installed (got $N)"
check "settings.json is valid JSON" jq empty "$PUKU_DIR/settings.json"

# --- install idempotent ---
bash "$REPO_DIR/scripts/install.sh" >/dev/null
N="$(jq '[.hooks | to_entries[] | .value[]] | length' "$PUKU_DIR/settings.json")"
[ "$N" = "7" ] && ok "reinstall idempotent (7 entries)" || bad "reinstall idempotent (got $N)"

# --- preserve unrelated hooks ---
jq '.hooks.SessionStart += [{hooks: [{type: "command", command: "/other/tool.sh"}]}]' \
  "$PUKU_DIR/settings.json" > "$WORK/s.json" && mv "$WORK/s.json" "$PUKU_DIR/settings.json"
bash "$REPO_DIR/scripts/install.sh" >/dev/null
grep -q /other/tool.sh "$PUKU_DIR/settings.json" && ok "unrelated hook preserved" || bad "unrelated hook preserved"

# --- status ---
check "status runs" bash "$REPO_DIR/scripts/install.sh" --status

# --- uninstall ---
check "uninstall runs" bash "$REPO_DIR/scripts/install.sh" --uninstall
check "hook removed" bash -c "! test -e '$PUKU_DIR/hooks/herdr-agent-state.sh'"
check "puku.toml removed" bash -c "! test -e '$TOML_DEST'"
grep -q /other/tool.sh "$PUKU_DIR/settings.json" && ok "unrelated hook survives uninstall" || bad "unrelated hook survives uninstall"
grep -q herdr-agent-state.sh "$PUKU_DIR/settings.json" && bad "adapter hooks removed" || ok "adapter hooks removed"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" = "0" ]
