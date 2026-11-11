#!/bin/bash
# herdr-agent-state.sh — Puku CLI → Herdr TUI state reporter.
#
# WHAT THIS IS
#   A small bridge, invoked by puku-cli at each lifecycle event, that reports
#   the agent's state to Herdr so Herdr can show it in the sidebar, tab and
#   workspace rollups, notifications, and `herdr agent wait`.
#
# WHY IT EXISTS
#   Puku is not a Herdr-supported agent, so Herdr has no bundled process
#   detection, screen manifest, or integration for it. The only supported way
#   for an external agent to drive Herdr state is the `pane report-agent`
#   channel, which is exactly what this script uses.
#
# STYLE RULES (do not weaken)
#   * Never write to stdout — puku-cli tool results must not be polluted.
#   * Never print to the terminal in a way the user did not ask for.
#   * Always exit 0 — a hook that fails must never break a puku-cli session.
#   * Stay synchronous-cheap and fire-and-forget — puku-cli runs hooks
#     synchronously on its hot path, so we background the Herdr call.
#
# STATE PROTOCOL (semantic state Herdr understands: idle, working, blocked)
#   SessionStart       → working   new session; identity established
#   UserPromptSubmit   → working   user asked for something; turn begins
#   PreToolUse         → working   a tool call is about to run
#   Elicitation        → blocked   model asked the user a structured question
#   PermissionRequest  → blocked   permission dialog appeared; user must decide
#   StopFailure        → blocked   turn ended because of an error
#   Stop               → idle      turn ended normally; ready for input
#   SessionEnd         → release   session over; hand the pane back to a shell.
#                        Herdr clears the pane's agent state immediately
#                        instead of waiting for its idle-prompt heuristic.
#   (anything else)    → no-op
#
# ORDERING
#   Herdr ignores reports whose --seq is not higher than the last accepted
#   seq from the same source. Hook fires can be reordered, so every report
#   carries a millisecond timestamp as --seq.
#
# ENVIRONMENT (injected by Herdr into every pane; puku-cli inherits them)
#   HERDR_ENV=1        set inside Herdr-managed panes; absent elsewhere
#   HERDR_PANE_ID      public pane id, e.g. "w1:p1"
#   HERDR_BIN_PATH     path to the running Herdr binary (preferred over PATH)
#
# OUTSIDE HERDR
#   When HERDR_ENV != 1 or HERDR_PANE_ID is missing we exit silently. That is
#   what keeps plain (non-Herdr) puku-cli sessions untouched by us.

set -u

# --- Early exit: we can only report from inside a Herdr pane. ----------------
if [ "${HERDR_ENV:-}" != "1" ] || [ -z "${HERDR_PANE_ID:-}" ]; then
  exit 0
fi

# --- Identity ------------------------------------------------------------------
# --agent is the display name users see; use our own, not a supported agent's.
# --source identifies this integration; stable, unique, must not start with
# "herdr:" (reserved for Herdr's own integrations).
SOURCE="puku:adapter"
AGENT="puku"

# --- Monotonic-ish sequence number (integer microsecond timestamp). -----------
# Relevance, not precision, is all we need: Herdr ignores out-of-order reports
# whose seq is not higher than the last accepted one. NOT portable via
# `date +%s%N` (BSD date on macOS prints a literal "N").
if [ -n "${EPOCHREALTIME:-}" ]; then
  SEQ="${EPOCHREALTIME/./}"                                 # bash ≥5, µs
elif command -v perl >/dev/null 2>&1; then
  SEQ="$(perl -MTime::HiRes=time -e 'printf "%d", time()*1e6')"  # macOS/Linux
else
  SEQ="$(date +%s)000000"                                   # coarse fallback
fi

# --- Prefer the Herdr binary Herdr itself injected; fall back to PATH. -------
HERDR_BIN="${HERDR_BIN_PATH:-herdr}"

# --- Read the hook payload puku-cli wrote to stdin. ---------------------------
INPUT="$(cat)"
EVENT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
TOOL="$(printf '%s' "$INPUT"  | jq -r '.tool_name // empty'       2>/dev/null)"

# --- report <state> [message] -------------------------------------------------
# Fire-and-forget: background the CLI call, discard all output, never fail.
report() {
  local state="$1" message="${2:-}"
  if [ -n "$message" ]; then
    "$HERDR_BIN" pane report-agent "$HERDR_PANE_ID" \
      --source "$SOURCE" --agent "$AGENT" \
      --state "$state" --seq "$SEQ" --message "$message" \
      >/dev/null 2>&1 &
  else
    "$HERDR_BIN" pane report-agent "$HERDR_PANE_ID" \
      --source "$SOURCE" --agent "$AGENT" \
      --state "$state" --seq "$SEQ" \
      >/dev/null 2>&1 &
  fi
}

# --- release -------------------------------------------------------------------
# End this source's lifecycle authority for the pane: Herdr clears the agent
# state right away instead of detecting the shell prompt on its own.
release() {
  "$HERDR_BIN" pane release-agent "$HERDR_PANE_ID" \
    --source "$SOURCE" --agent "$AGENT" --seq "$SEQ" \
    >/dev/null 2>&1 &
}

case "$EVENT" in
  SessionStart|UserPromptSubmit|PreToolUse)
    report working
    ;;
  Elicitation)
    # The model asked a structured question; nothing to do until the user answers.
    report blocked "waiting for answer"
    ;;
  PermissionRequest)
    # Permission dialog is up; include the tool name so the sidebar/tooltip
    # says *what* is asking, when the payload tells us.
    report blocked "permission request${TOOL:+: $TOOL}"
    ;;
  StopFailure)
    report blocked "turn ended with error"
    ;;
  Stop)
    report idle
    ;;
  SessionEnd)
    release
    ;;
  *)
    # Unknown or intentionally unmapped event (e.g. PostToolUse, SubagentStart).
    # The main agent already reported 'working' upstream, which is correct.
    exit 0
    ;;
esac

exit 0
