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
- `herdr agent explain <pane> --json` reports `puku` as a lifecycle authority with the hook source `puku:adapter`.

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

- Native session restore (resume Puku after a Herdr restart) is **not** supported: puku-cli documents no session-resume flag, so there is no correct resume command to hand Herdr.
- The screen-detection fallback was removed: Herdr cannot identify Puku's process, so a detection manifest would never match.

## License

MIT.
