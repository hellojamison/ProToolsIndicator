# Pro Tools Indicator

Small Swift package for a macOS menu bar status light and its agent-facing command line controller.

## Repo map

- `Sources/IndicatorCore/` — shared on-disk status format and storage.
- `Sources/ProToolsIndicator/` — SwiftUI menu bar app.
- `Sources/PTIndicatorCLI/` — `pt-indicator on|off|status` command.

## Commands

- Build app and CLI: `./scripts/build-app.sh`
- Run the menu bar app: `open dist/ProToolsIndicator.app`
- Control the queue: `./dist/bin/pt-indicator request [--minutes <1-1440>] <agent-and-chat-title>|wait <ticket>|eta <ticket> <minutes|unknown>|release <ticket> --closeout <outcome> [--reason "why the session remains open"]|cancel <ticket>|status`

## Testing and verification

There is no test target. Verify changes with the package build and, when available, a manual menu bar check.

## Hard rules

- Reservation ownership is manually controlled. The app detects open Pro Tools application processes, but does not inspect session content or infer which agent is using Pro Tools.
- Agents own their ETA reports. `--minutes` estimates expected work duration and queue priority; the active owner can update remaining time with `pt-indicator eta <ticket> <minutes|unknown>`. Status and the menu bar popover show the current agent, reported ETA, and projected queue starts.
- Identify every request with your agent name and exact current chat title, for example `"Codex: Improve menu bar icon"`. The holder and queue display this text so users can tell which conversation is using or waiting for Pro Tools.
- Releasing a turn requires an explicit closeout report. Before handing off, agents must save needed work, close sessions they opened when safe, and verify those sessions are closed. Never infer whether a session needed saving; record the agent's stated outcome and show it in status. Preserve other users' sessions and uncertain unsaved work. If a session must remain open, the agent must provide a specific reason; CLI releases using either `left-open-*` outcome require `--reason` with 8–280 characters.
- Queue all CLI requests through `IndicatorStore.request`; do not add a direct CLI path that can skip waiting requests.
- Keep every queue read-modify-write operation inside the file lock so simultaneous agents do not lose queue entries.
- State is local to the current macOS user in Application Support; do not add a network listener or write outside that location without a clear requirement.
- Do not add credentials or secrets.
