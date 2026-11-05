# Pro Tools Indicator

Small Swift package for a macOS menu bar status light and its agent-facing command line controller.

## Repo map

- `Sources/IndicatorCore/` — shared on-disk status format and storage.
- `Sources/ProToolsIndicator/` — SwiftUI menu bar app.
- `Sources/PTIndicatorCLI/` — `pt-indicator on|off|status` command.

## Commands

- Build app and CLI: `./scripts/build-app.sh`
- Run the menu bar app: `open dist/ProToolsIndicator.app`
- Control the state: `./dist/bin/pt-indicator on|off|status`

## Testing and verification

There is no test target. Verify changes with the package build and, when available, a manual menu bar check.

## Hard rules

- The indicator is manually controlled. Do not claim it detects Pro Tools sessions or agent activity automatically.
- State is local to the current macOS user in Application Support; do not add a network listener or write outside that location without a clear requirement.
- Do not add credentials or secrets.
