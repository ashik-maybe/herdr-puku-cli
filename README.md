# herdr-puku-cli

[Puku CLI](https://puku.sh/puku-cli/) state reporting for [Herdr TUI](https://herdr.dev/tui/). Puku is not in Herdr's supported agent list, so Herdr has nothing built in to show Puku's state — this adapter does it.

## How it works

Puku CLI fires a hook for every lifecycle event (`SessionStart`, `PreToolUse`, `PermissionRequest`, `Stop`, …). Puku writes the event as JSON on the hook's stdin. `bin/herdr-agent-state.sh` reads it and reports the mapped state over Herdr's pane-reporting socket:

```
puku-cli event ─▶ hook (our script) ─▶ herdr pane report-agent ─▶ sidebar / tab / workspace rollup
```

State mapping: `working` while Puku thinks or runs tools, `blocked` when Puku waits for you (permission dialog, or a structured question), `idle` when the turn ends. `SessionEnd` releases Herdr's lifecycle authority immediately instead of waiting for its idle-prompt heuristic. Outside Herdr panes (no `HERDR_PANE_ID`) the hook exits silently and does nothing.

## Compatibility

| Component | Status |
|---|---|
| puku-cli | tested against **1.8.68** (`@puku/puku-cli`, hook payload schema verified from the published bundle) |
| Herdr | **≥ 0.7.0** (manifest floor); developed and verified against 0.9.5 |
| Session restore | verified live in a container; **not yet smoke-tested against a real puku account** — `puku-cli --resume <id>` needs a signed-in session |

## Install

Two ways. Pick one.

### As a Herdr plugin (from git)

```bash
herdr plugin install ashik-maybe/herdr-puku-cli
herdr plugin action invoke herdr-puku-cli.setup
```

### As a plain script

```bash
cd herdr-puku-cli
./scripts/install.sh
```

Either way, restart puku-cli afterwards. The plugin install itself does not wire up hooks — run the `.setup` action once (the plain install does it).

## Uninstall

```bash
./scripts/install.sh --uninstall
# or, as a plugin:
herdr plugin action invoke herdr-puku-cli.remove
```

Removes only what this adapter added: its hook entries in `~/.puku-cli/settings.json` and the hook script. Other hooks, unrelated settings, and a hand-edited settings.json are left untouched. A timestamped backup (`settings.json.bak.<ts>`) is created before any change.

## Check

```bash
./scripts/install.sh --status
# or, as a plugin:
herdr plugin action invoke herdr-puku-cli.status
```

## Development

```bash
./tests/run.sh   # plain bash suite; sandboxes into a temp HOME, touches nothing

# Try the plugin for real on a Herdr host:
herdr plugin link /path/to/herdr-puku-cli
herdr plugin action invoke herdr-puku-cli.status
```

```
.github/workflows/     CI: shellcheck + tests on push/PR
herdr-plugin.toml      Herdr plugin manifest (actions: setup, remove, status)
LICENSE                MIT
CHANGELOG.md           Release history
bin/herdr-agent-state.sh  Puku lifecycle hook → herdr pane report-agent
scripts/lib.sh         Shared install logic (paths, settings.json merge)
scripts/install.sh     install / uninstall / status entrypoint
tests/run.sh           Test suite
```

## Notes

- Verify with `herdr agent list` / `herdr pane get <pane>`. `herdr agent explain` is not available for unsupported custom agents (`agent_not_found` / `agent_explain_unavailable`) — that's a Herdr limitation, not a bug.
- Reports hold only while puku-cli actually runs in the pane: when the pane returns to a plain shell prompt, Herdr clears the agent state after a second or two (same as its built-in integrations).
- `SessionStart` carries `session_id` and `transcript_path`, so the adapter also reports `--agent-session-id` / `--agent-session-path` plus resume argv `puku-cli --resume <id>`. After a Herdr server restart, Herdr can reopen the pane in the same cwd with the native puku resume command.
- Sidebar/tab display is wired up via `report-metadata`: `display_agent=puku` and `title="puku (<model>)"` while the session runs, cleared on `SessionEnd`.
- `Notification` with `notification_type` `permission_prompt` or `elicitation_dialog` reports `blocked` (belt-and-braces alongside `PermissionRequest`/`Elicitation`); other notification types are ignored.
- Screen detection is deliberately absent: Herdr cannot identify Puku's process, so a detection manifest would never match.
