# herdr-puku-cli

[Puku CLI](https://puku.sh/puku-cli/) state reporting for [Herdr TUI](https://herdr.dev/tui/). Puku is not in Herdr's supported agent list, so Herdr has nothing built in to show Puku's state — this adapter does it.

Code comments carry the deep documentation. This file covers install, uninstall, and usage.

## Usage

Once installed (see below), everything is automatic:

- Herdr shows Puku's state in the pane and the sidebar, rolled up into tabs and workspaces:
  - `working` while Puku thinks or runs tools
  - `blocked` when Puku waits for you — permission dialog, or a structured question
  - `idle` when the turn ends; Puku is ready for your next message
- When the Puku session ends, its agent state is cleared from the pane right away.
- `herdr agent list` shows the pane's agent as `puku`.
- Note: `herdr agent explain` is not available for unsupported custom agents (it answers `agent_not_found` / `agent_explain_unavailable`). Verify with `herdr agent list` or `herdr pane get <pane>` instead.
- Reports only hold while puku-cli actually runs in the pane: when the pane returns to a plain shell prompt, Herdr clears the agent state after a second or two (same as its built-in integrations).

Outside Herdr panes the hook does nothing.

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

Either way, restart puku-cli afterwards. The plugin install itself does not wire up hooks — run the `.setup` action once (plain install does it).

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

For discovery in the Herdr marketplace, the GitHub repo needs the `herdr-plugin` topic (public repos with the topic and a `herdr-plugin.toml` get indexed).

Layout:

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

- Native session restore is wired up: `SessionStart` payloads carry `session_id` and `transcript_path`, so the adapter reports `--agent-session-id <id> --agent-session-path <transcript> -- puku-cli --resume <id>` to Herdr. After a Herdr server restart, Herdr can resume the pane with the native puku resume command in the same cwd. Fires only for `SessionStart` with a well-formed session id; `--resume` support verified against puku-cli 1.8.68 (`dist/cli.mjs`) and smoke-tested live in a container.
- Sidebar/tab display is wired up via `report-metadata`: `display_agent=puku` and `title="puku (<model>)"` while the session runs (model from the payload), cleared on `SessionEnd`.
- `Notification` with `notification_type` `permission_prompt` or `elicitation_dialog` reports `blocked` (belt-and-braces alongside `PermissionRequest`/`Elicitation`); other notification types are ignored.
- The screen-detection fallback was removed: Herdr cannot identify Puku's process, so a detection manifest would never match.