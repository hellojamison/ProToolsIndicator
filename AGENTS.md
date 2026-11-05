# Pro Tools Indicator

Small Swift package for a macOS menu bar status light and its agent-facing command line controller.

## Repo map

- `Sources/IndicatorCore/` — shared on-disk status format and storage.
- `Sources/ProToolsIndicator/` — SwiftUI menu bar app.
- `Sources/PTIndicatorCLI/` — `pt-indicator on|off|status` command.

## Commands

- Build app and CLI: `./scripts/build-app.sh`
- Run the menu bar app: `open dist/ProToolsIndicator.app`
- Control the queue: `./dist/bin/pt-indicator request [--minutes <1-1440>] <who>|wait <ticket>|eta <ticket> <minutes|unknown>|release <ticket> --closeout <outcome>|cancel <ticket>|status`

## Testing and verification

There is no test target. Verify changes with the package build and, when available, a manual menu bar check.

## Hard rules

- Reservation ownership is manually controlled. The app detects open Pro Tools application processes, but does not inspect session content or infer which agent is using Pro Tools.
- Agents own their ETA reports. `--minutes` estimates expected work duration and queue priority; the active owner can update remaining time with `pt-indicator eta <ticket> <minutes|unknown>`. Status and the menu bar popover show the current agent, reported ETA, and projected queue starts.
- Releasing a turn requires an explicit closeout report. Never infer whether a session needed saving; record the agent's stated outcome and show it in status. Remind agents to save needed work and close sessions they opened when safe, while preserving other users' sessions and uncertain unsaved work.
- Queue all CLI requests through `IndicatorStore.request`; do not add a direct CLI path that can skip waiting requests.
- Keep every queue read-modify-write operation inside the file lock so simultaneous agents do not lose queue entries.
- State is local to the current macOS user in Application Support; do not add a network listener or write outside that location without a clear requirement.
- Do not add credentials or secrets.
