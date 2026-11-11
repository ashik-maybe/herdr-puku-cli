#!/bin/bash
# tests/run.sh — plain bash test suite for herdr-puku-cli.
#
# Runs everything against a throwaway HOME (mktemp -d), so your real
# ~/.puku-cli and ~/.config/herdr are never touched. Requires jq.
# Exits 0 when every assertion passes, 1 otherwise.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT   # always clean the sandbox, pass or fail

# --- Sandbox all destination paths into the temp HOME. ------------------------
export HOME="$WORK"
export PUKU_DIR="$WORK/.puku-cli"
export TOML_DEST="$WORK/.config/herdr/agent-detection/puku.toml"   # legacy path

PASS=0 FAIL=0

ok()  { PASS=$((PASS+1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %s\n' "$1"; }
check() { # check <name> <command...> — passes if the command exits 0
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi
}

echo "== hook: no-op outside Herdr =="
out="$(printf '{"hook_event_name":"Stop"}' | bash "$REPO_DIR/bin/herdr-agent-state.sh"; echo "exit=$?")"
[ "$out" = "exit=0" ] && ok "hook exits 0 silently outside herdr" || bad "hook exits 0 silently outside herdr"

echo "== hook: reports states inside Herdr (with a stub 'herdr' binary) =="
# We stub `herdr` on PATH and capture every invocation. The hook backgrounds
# the call, so give it a moment before asserting.
STUB_BIN="$WORK/stub-bin"; mkdir -p "$STUB_BIN"
cat > "$STUB_BIN/herdr" <<'EOF'
#!/bin/bash
echo "$@" >> "$STUB_LOG"
EOF
chmod +x "$STUB_BIN/herdr"
export STUB_LOG="$WORK/herdr.log"; : > "$STUB_LOG"

run_hook() { # run_hook <json payload>
  echo "$1" | PATH="$STUB_BIN:$PATH" HERDR_ENV=1 HERDR_PANE_ID=p1 bash "$REPO_DIR/bin/herdr-agent-state.sh"
  sleep 0.2
}

run_hook '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
check "PreToolUse reports working"            grep -q -- "--state working" "$STUB_LOG"
check "PreToolUse includes --seq"             grep -q -- "--seq " "$STUB_LOG"

run_hook '{"hook_event_name":"PermissionRequest","tool_name":"Bash"}'
check "PermissionRequest reports blocked"     grep -q -- "--state blocked" "$STUB_LOG"
check "blocked message names the tool"        grep -q "permission request: Bash" "$STUB_LOG"

: > "$STUB_LOG"
run_hook '{"hook_event_name":"Elicitation"}'
check "Elicitation reports blocked"           grep -q -- "--state blocked" "$STUB_LOG"

: > "$STUB_LOG"
run_hook '{"hook_event_name":"StopFailure"}'
check "StopFailure reports blocked"           grep -q -- "--state blocked" "$STUB_LOG"

: > "$STUB_LOG"
run_hook '{"hook_event_name":"Stop"}'
check "Stop reports idle"                     grep -q -- "--state idle" "$STUB_LOG"

: > "$STUB_LOG"
run_hook '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
check "Notification permission_prompt blocked" grep -q -- "--state blocked" "$STUB_LOG"

: > "$STUB_LOG"
run_hook '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
check "Notification idle_prompt is a no-op"   test ! -s "$STUB_LOG"

: > "$STUB_LOG"
run_hook '{"hook_event_name":"SessionStart","session_id":"abc-123-def"}'
check "SessionStart reports working + resume argv" bash -c "grep -q -- '--state working' '$STUB_LOG' && grep -q -- '-- puku-cli --resume abc-123-def' '$STUB_LOG' && grep -q -- '--agent-session-id abc-123-def' '$STUB_LOG'"

: > "$STUB_LOG"
run_hook '{"hook_event_name":"SessionEnd"}'
check "SessionEnd releases the agent"         grep -q "release-agent" "$STUB_LOG"

echo "== install =="
check "install runs"                          bash "$REPO_DIR/scripts/install.sh"
check "hook copied and executable"            test -x "$PUKU_DIR/hooks/herdr-agent-state.sh"
N="$(jq '[.hooks | to_entries[] | .value[]] | length' "$PUKU_DIR/settings.json")"
[ "$N" = "9" ] && ok "9 hook entries installed" || bad "9 hook entries installed (got $N)"
check "settings.json is valid JSON"           jq empty "$PUKU_DIR/settings.json"

echo "== install is idempotent =="
bash "$REPO_DIR/scripts/install.sh" >/dev/null
N="$(jq '[.hooks | to_entries[] | .value[]] | length' "$PUKU_DIR/settings.json")"
[ "$N" = "9" ] && ok "reinstall keeps 9 entries" || bad "reinstall keeps 9 entries (got $N)"

echo "== unrelated hooks survive everywhere =="
jq '.hooks.SessionStart += [{hooks: [{type: "command", command: "/other/tool.sh"}]}]' \
  "$PUKU_DIR/settings.json" > "$WORK/s.json" && mv "$WORK/s.json" "$PUKU_DIR/settings.json"
bash "$REPO_DIR/scripts/install.sh" >/dev/null
grep -q /other/tool.sh "$PUKU_DIR/settings.json" && ok "unrelated hook preserved on install" || bad "unrelated hook preserved on install"

echo "== status =="
check "status runs"                           bash "$REPO_DIR/scripts/install.sh" --status

echo "== uninstall =="
check "uninstall runs"                        bash "$REPO_DIR/scripts/install.sh" --uninstall
check "hook removed"                          bash -c "! test -e '$PUKU_DIR/hooks/herdr-agent-state.sh'"
grep -q /other/tool.sh "$PUKU_DIR/settings.json" && ok "unrelated hook survives uninstall" || bad "unrelated hook survives uninstall"
grep -q herdr-agent-state.sh "$PUKU_DIR/settings.json" && bad "adapter hooks removed" || ok "adapter hooks removed"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" = "0" ]
