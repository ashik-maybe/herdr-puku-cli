#!/bin/bash
# herdr-agent-state.sh — Puku CLI lifecycle hook → Herdr TUI state reporter.
#
# Reads Puku hook payload on stdin (JSON), maps the event to a Herdr
# agent state, and reports it via `herdr pane report-agent`.
# No-op outside a Herdr pane (HERDR_ENV != 1).
# Always exits 0 — this script must never break a Puku session.
#
# Event → state map:
#   SessionStart       → working  (session identity recorded)
#   UserPromptSubmit   → working
#   PreToolUse         → working
#   Stop               → idle
#   PermissionRequest  → blocked
#   StopFailure        → blocked
#   SessionEnd         → idle
#   PostToolUseFailure → (no-op: model still handles the error, stays working)
#
# See docs in README.md.

set -u

# Outside Herdr: nothing to report.
if [ "${HERDR_ENV:-}" != "1" ] || [ -z "${HERDR_PANE_ID:-}" ]; then
  exit 0
fi

INPUT="$(cat)"
EVENT="$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"

STATE=""
case "$EVENT" in
  SessionStart|UserPromptSubmit|PreToolUse)
    STATE="working"
    ;;
  Stop|SessionEnd)
    STATE="idle"
    ;;
  PermissionRequest|StopFailure)
    STATE="blocked"
    ;;
  *)
    # Unknown or intentionally unmapped event.
    exit 0
    ;;
esac

# Fire-and-forget: Puku hooks run synchronously, keep latency at zero.
HERDR_BIN="${HERDR_BIN_PATH:-herdr}"
"$HERDR_BIN" pane report-agent "$HERDR_PANE_ID" \
  --source puku:adapter \
  --agent puku \
  --state "$STATE" >/dev/null 2>&1 &

exit 0
