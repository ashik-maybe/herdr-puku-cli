# puku-cli-adapter-for-herdrtui

[Puku CLI](https://puku.sh/puku-cli) state reporter for [Herdr TUI](https://herdr.dev/tui/). Puku is not in Herdr's supported agent list. This adapter fills the gap.

## Install

### As a Herdr plugin (from git)

```bash
herdr plugin install <owner>/puku-cli-adapter-for-herdrtui --ref plugin-support
herdr plugin action invoke puku.adapter.setup
herdr server reload-agent-manifests
```

Restart Herdr instead of reloading if reload fails. The other actions:

```bash
herdr plugin action invoke puku.adapter.status
herdr plugin action invoke puku.adapter.remove
```

For local development, link a checkout instead of installing:

```bash
herdr plugin link /path/to/puku-cli-adapter-for-herdrtui
```

### As a plain script

```bash
cd puku-cli-adapter-for-herdrtui
./scripts/install.sh
herdr server reload-agent-manifests
```

## How it works

Puku runs `bin/herdr-agent-state.sh` at each lifecycle event. The script maps the event to a Herdr state and reports it.

| Puku event                                 | Herdr state |
| ------------------------------------------ | ----------- |
| SessionStart, UserPromptSubmit, PreToolUse | `working`   |
| PermissionRequest, StopFailure             | `blocked`   |
| Stop, SessionEnd                           | `idle`      |

Outside Herdr panes the script exits silently. It never writes to stdout, so it never interferes with Puku tool results.

`config/puku.toml` is the fallback. When hooks are absent, Herdr reads Puku's prompt markers from the screen instead.

Note: installing the plugin does not wire up Puku hooks by itself. Run the `puku.adapter.setup` action (or `./scripts/install.sh`) once after install. Plugin v1 cannot register Puku hooks or agent-detection manifests; both are applied by the setup action.

## Verify

```bash
herdr agent list
herdr agent explain <pane> --json
```

`explain` shows the matched rule, the manifest source, and the fallback reason when no rule matches.

## Uninstall

```bash
./scripts/install.sh --uninstall   # or: herdr plugin action invoke puku.adapter.remove
```

Removes only what install added. Other hooks stay untouched. A user-edited `puku.toml` stays in place with a note printed.

`./scripts/install.sh --status` shows the current install state.

## Layout

```
herdr-plugin.toml        Herdr plugin manifest (actions: setup, remove, status)
bin/herdr-agent-state.sh Puku lifecycle hook → herdr pane report-agent
config/puku.toml         Herdr agent-detection manifest (screen fallback)
scripts/lib.sh           Shared install logic (paths, settings.json merge)
scripts/install.sh       install / uninstall / status entrypoint
tests/run.sh             Plain bash tests; runs against a temp HOME
```

## Tests

```bash
./tests/run.sh
```

Requires `jq`. Uses a temporary HOME; your real `~/.puku-cli` is never touched.

## License

MIT.

<details><summary>CONTEXT</summary>

## Summary

This adapter reports Puku CLI activity to Herdr TUI. Puku is not a supported Herdr agent. The adapter adds support.

## Terms

| Term               | Definition                                                                     |
| ------------------ | ------------------------------------------------------------------------------ |
| Adapter            | Software that connects two programs and translates between them.               |
| Hook               | A script that runs at a named lifecycle event. Puku sends a payload on stdin.  |
| Lifecycle state    | One of `working`, `blocked`, `idle`, `done`.                                   |
| Detection manifest | Rules that map screen text to a state. Herdr reads the pane bottom buffer.     |
| Herdr TUI          | The terminal multiplexer at herdr.dev/tui. It shows agent states in a sidebar. |
| Puku CLI           | The terminal coding agent at puku.sh. It runs hooks at lifecycle events.       |
| Pane               | One real terminal inside Herdr.                                                |
| Source             | The reporter id the adapter sends with each state report.                      |

## Steps

1. The setup action copies the hook script to `~/.puku-cli/hooks/herdr-agent-state.sh`.
2. The setup action adds hook entries to `~/.puku-cli/settings.json`. It backs up the file first.
3. The setup action copies `config/puku.toml` to `~/.config/herdr/agent-detection/puku.toml`.
4. Puku runs the hook script at each lifecycle event. The script reads the payload on stdin.
5. The script checks `HERDR_ENV`. When the value is not `1`, the script exits silently.
6. The script maps the event to a state. It sends the state with `herdr pane report-agent`.
7. Herdr shows the state in the sidebar and rolls it up to the tab and workspace.
8. Run the remove action to uninstall the adapter. The uninstall removes only adapter entries.

</details>
