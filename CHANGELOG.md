# Changelog

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
