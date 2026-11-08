# puku-cli-adapter-for-herdrtui

[Puku CLI](https://puku.sh/puku-cli) state reporter for [Herdr TUI](https://herdr.dev/tui/). Puku is not in Herdr's supported agent list. This adapter fills the gap.

## Install

One command installs the hook script, the hook entries in Puku settings, and the detection manifest.

```bash
cd puku-cli-adapter-for-herdrtui
./install.sh
herdr server reload-agent-manifests
```

Restart Herdr instead of reloading if reload fails.

## How it works

Puku runs `herdr-agent-state.sh` at each lifecycle event. The script maps the event to a Herdr state and reports it.

| Puku event                                 | Herdr state |
| ------------------------------------------ | ----------- |
| SessionStart, UserPromptSubmit, PreToolUse | `working`   |
| PermissionRequest, StopFailure             | `blocked`   |
| Stop, SessionEnd                           | `idle`      |

Outside Herdr panes the script exits silently. It never writes to stdout, so it never interferes with Puku tool results.

`puku.toml` is the fallback. When hooks are absent, Herdr reads Puku's prompt markers from the screen instead.

## Verify

```bash
herdr agent list
herdr agent explain <pane> --json
```

`explain` shows the matched rule, the manifest source, and the fallback reason when no rule matches.

## Uninstall

```bash
./install.sh --uninstall
```

Removes only what install added. Other hooks stay untouched. A user-edited `puku.toml` stays in place with a note printed.

`./install.sh --status` shows the current install state.

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

1. The install script copies the hook script to `~/.puku-cli/hooks/herdr-agent-state.sh`.
2. The install script adds hook entries to `~/.puku-cli/settings.json`. It backs up the file first.
3. The install script copies `puku.toml` to `~/.config/herdr/agent-detection/puku.toml`.
4. Puku runs the hook script at each lifecycle event. The script reads the payload on stdin.
5. The script checks `HERDR_ENV`. When the value is not `1`, the script exits silently.
6. The script maps the event to a state. It sends the state with `herdr pane report-agent`.
7. Herdr shows the state in the sidebar and rolls it up to the tab and workspace.
8. Run `./install.sh --uninstall` to remove the adapter. The uninstall removes only adapter entries.

</details>
