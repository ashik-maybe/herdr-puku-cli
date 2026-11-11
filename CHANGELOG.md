# Changelog

## 0.3.2

- `SessionStart` reports `--agent-session-path <transcript_path>` alongside `--agent-session-id` (native resume now knows the session file).
- `SessionStart` reports display metadata: `herdr pane report-metadata --display-agent puku --title "puku (<model>)"` (model from payload, truncated); `SessionEnd` clears both. Verified live: `herdr agent list` shows the title and display agent while the session runs, gone after SessionEnd.

## 0.3.1

- `SessionStart` now also reports `--agent-session-id <sid>` plus resume argv `puku-cli --resume <sid>` to Herdr, enabling native pane resume after a server restart (puku-cli 1.8.68 supports `--resume <id>`; payload `session_id` verified from the bundle's hook schema).
- `Notification` with `notification_type` `permission_prompt` or `elicitation_dialog` reports `blocked`; other types ignored. Registered in settings.json merge (9 hook entries).
- Removed `herdr agent explain` from verification docs — unavailable for unsupported custom agents.
- Documented that reports hold only while puku-cli runs in the pane (Herdr's shell-prompt safety net clears agent state).

## 0.3.0

- Renamed the project / plugin to `herdr-puku-cli`.
- Uses Herdr's lifecycle API properly: millisecond `--seq` on every state report (ordering-safe), `pane release-agent` on SessionEnd, `Elicitation` mapped to `blocked`, `--message` with the tool name on permission requests.
- Dropped the screen-detection manifest (`config/puku.toml`): Herdr cannot identify an unknown puku process.
- README refocused on install / uninstall / usage; internals documented in code comments.

## 0.2.0

- Rebuilt as a modular Herdr plugin (`herdr-plugin.toml` with `setup`, `remove`, `status` actions) alongside the plain-script install path.
- Split install logic into `scripts/lib.sh` + `scripts/install.sh`; moved hook to `bin/`, manifest to `config/`.
- Added temp-HOME test suite (`tests/run.sh`), sandboxed from real user state.

## 0.1.0

- First version: puku-cli lifecycle hook reporting to `herdr pane report-agent`, plus an inert-screen-detection manifest.
