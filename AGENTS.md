# Pro Tools Indicator

Small Swift package for a macOS menu bar status light and its agent-facing command line controller.

## Repo map

- `Sources/IndicatorCore/` — shared on-disk status format and storage.
- `Sources/ProToolsIndicator/` — SwiftUI menu bar app.
- `Sources/IndicatorCore/ReleaseVerification.swift` — pure release decision (closeout × Pro Tools running × session probe) and probe output parsing.
- `Sources/PTIndicatorCLI/` — `pt-indicator` command (queue, release with closure check, status, check-session).
- `Tests/IndicatorCoreTests/` — unit tests for the release decision.

## Commands

- Build app and CLI: `./scripts/build-app.sh`
- Run the menu bar app: `open dist/ProToolsIndicator.app`
- Control the queue: `./dist/bin/pt-indicator request [--minutes <1-1440>] <agent-and-chat-title>|wait <ticket>|eta <ticket> <minutes|unknown>|release <ticket> --closeout <outcome> [--reason "why the session remains open"]|cancel <ticket>|status|check-session`

## Testing and verification

Run `swift test` (release decision and probe parsing) and `swift build`; rebuild `dist/` with `./scripts/build-app.sh`, which swaps binaries atomically. When available, also do a manual menu bar check. Point `PT_INDICATOR_SESSION_PROBE` at a fake script to exercise the session check without Pro Tools.

## Hard rules

- Reservation ownership is manually controlled. The app detects open Pro Tools application processes. When a CLI release claims the session is closed (`no-session`, `saved-and-closed`, `no-save-needed-and-closed`) and Pro Tools is running, the CLI asks Pro Tools read-only via PTSL whether a session is open (ptxExtractor's `ptx-track-group-live-matrix current-session-path`, overridable with `PT_INDICATOR_SESSION_PROBE`, 10 s timeout). An open session refuses the release and the ticket stays held; a missing, failed or timed-out check accepts the release but records the closure as not verified. It never reads session content or infers who is using Pro Tools. Run the check outside the queue lock, and never let it block indefinitely.
- Request a turn only when you are ready to use Pro Tools. Do builds, tests, code changes and other prep before `request`, not while holding the turn. If you need to rebuild or do long non-Pro Tools work mid-turn, release (with an honest closeout) and request again when ready. `--minutes` should cover only the hands-on Pro Tools time.
- Agents own their ETA reports. `--minutes` estimates expected work duration and queue priority; the active owner can update remaining time with `pt-indicator eta <ticket> <minutes|unknown>`. Status and the menu bar popover show the current agent, reported ETA, and projected queue starts.
- Identify every request with your agent name and exact current chat title, for example `"Codex: Improve menu bar icon"`. The holder and queue display this text so users can tell which conversation is using or waiting for Pro Tools.
- Releasing a turn requires an explicit closeout report. Before handing off, agents must save needed work, close sessions they opened when safe, and verify those sessions are closed. Never infer whether a session needed saving; record the agent's stated outcome and show it in status. Preserve other users' sessions and uncertain unsaved work. If a session must remain open, the agent must provide a specific reason; CLI releases using either `left-open-*` outcome require `--reason` with 8–280 characters.
- Agent closeout guidance: confirm closure by the open session path (`pt-indicator check-session`), not by looking for Edit or Mix windows; quit Pro Tools if you launched it; stop your own watchers, helpers and test apps before release; if a close call times out or its result is uncertain, report a `left-open-*` outcome with a reason.
- Queue all CLI requests through `IndicatorStore.request`; do not add a direct CLI path that can skip waiting requests.
- Keep every queue read-modify-write operation inside the file lock so simultaneous agents do not lose queue entries.
- State is local to the current macOS user in Application Support; do not add a network listener or write outside that location without a clear requirement.
- Do not add credentials or secrets.
