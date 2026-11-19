# Pro Tools Indicator

A tiny macOS menu bar light that agents can control with `pt-indicator`. The light has two colors: red means someone holds the Pro Tools turn, green means nobody does. Whether Pro Tools is open is shown as text in the popover, not as a color. Requests are granted in FIFO order. The app detects whether Pro Tools is open and which version (only one copy of Pro Tools can run at a time). It never reads session content or controls Pro Tools; the only thing it asks Pro Tools is whether a session is open, read-only, when a release claims the session was closed.

## Build and run

Requires macOS 13 or later and Swift 6.

```sh
./scripts/build-app.sh
open dist/ProToolsIndicator.app
```

To start the indicator automatically when you log in, tick **Open at Login** in its menu bar popover. macOS registers the app at its current path (`dist/ProToolsIndicator.app`), so rebuilding keeps it working; moving or deleting `dist/` does not.

In another terminal, request access and identify the agent plus the exact current chat title:

```sh
./dist/bin/pt-indicator request --minutes 5 "Claude: Improve menu bar icon"
./dist/bin/pt-indicator status
```

Request a turn only when you are ready to use Pro Tools. Finish builds, tests and other prep first so you don't hold Pro Tools while others wait. If you need a long rebuild or other non-Pro Tools work mid-turn, release with an honest closeout and request again when ready.

The optional `--minutes` value is the agent's expected Pro Tools work duration (hands-on Pro Tools time only, not build time). Waiting requests are ordered shortest estimate first; ties stay FIFO, and requests without an estimate follow estimated requests. When a request is granted, the same value starts as that agent's ETA. Update it while working with `pt-indicator eta <ticket> <minutes|unknown>`; the ETA is a self-reported estimate, not a countdown or time limit.

If Pro Tools is busy, `request` adds the caller to the queue and prints its ticket and position. `wait <ticket>` blocks until the turn is granted. `status` shows the current agent and their reported remaining-time ETA, plus each queued agent's projected start ETA and expected work duration. Queue ETAs are projections from agent estimates, not guarantees. Release requires a closeout report, for example `release <ticket> --closeout saved-and-closed`; the report is saved and shown in `status` so the next person can see whether the session was saved and closed. The available closeout values are `no-session`, `saved-and-closed`, `no-save-needed-and-closed`, `left-open-needs-save`, and `left-open-no-save-needed`. Before handoff, save needed work, close sessions you opened when safe, and verify they are closed. Preserve someone else's session and uncertain unsaved work. If a session must remain open, report the matching left-open state and give a specific reason with `--reason "..."` (8–280 characters). The reason is displayed in status and the menu bar handoff summary. `cancel <ticket>` removes a waiting request. The menu bar popover shows the current agent, their ETA, the waiting queue, and the open Pro Tools version. It lets the local user remove waiting entries or release to the next person with the same closeout report. An open app is shown separately from a reservation, so the queue can hand Pro Tools to an agent using an already-open session.

For scripts, request a ticket, wait if queued, do the Pro Tools work, close out the session, and report the outcome when releasing:

```sh
set -e
reservation=$(./dist/bin/pt-indicator request --minutes 5 "Claude: Improve menu bar icon")
ticket=${reservation##*ticket=}
case "$reservation" in
  queued*) ./dist/bin/pt-indicator wait "$ticket" ;;
esac
# Agent work that uses Pro Tools
# Update the reported remaining-time ETA during the turn:
./dist/bin/pt-indicator eta "$ticket" 3
# Save needed work, close sessions you opened, and verify closure before reporting:
./dist/bin/pt-indicator release "$ticket" --closeout saved-and-closed
```

If you cannot safely close a session, state the concrete reason before releasing:

```sh
./dist/bin/pt-indicator release "$ticket" --closeout left-open-needs-save --reason "The session contains unsaved edits that need the owner to review before closing."
```

Choose the closeout value that matches what actually happened.

### Closure check on release

When you release with a closed outcome (`no-session`, `saved-and-closed` or `no-save-needed-and-closed`) and Pro Tools is running, `pt-indicator` asks Pro Tools, read-only over PTSL, whether a session is open. It runs `~/Documents/Projects/ptxExtractor/Runtime/.build/debug/ptx-track-group-live-matrix current-session-path` (override the path with `PT_INDICATOR_SESSION_PROBE`) with a 10-second limit, outside the queue lock.

- A session is open: the release is refused (exit code 4), the message names the open session path, and your ticket stays held. Close the session and release again, or use a `left-open-*` outcome with `--reason`.
- Pro Tools is not running, or Pro Tools reports no open session: the release goes through and status shows it as verified.
- The check is missing, fails or times out: the release goes through, and status shows `Closure not verified.` with the reason.

`pt-indicator check-session` runs the same read-only check on its own: it prints the open session path (exit 5), says no session is open (exit 0), or says the check failed (exit 6). When nobody holds the turn but Pro Tools is running, `status` adds a line such as `Pro Tools 25.12.2 is running with no turn holder (left over?); last holder: ...`.

Before releasing:

- Confirm closure by the session path (`pt-indicator check-session`), not by whether Edit or Mix windows are showing.
- Quit Pro Tools if you launched it.
- Stop your own watchers, helpers and test apps.
- If a close call times out or you are not sure it worked, report a `left-open-*` outcome with a reason.

 An open-session reason does not replace the close-before-handoff requirement; it records why safe closure was not possible. If a command is interrupted while queued, cancel that waiting ticket. Never use a cleanup trap that releases an active turn without first reporting the session state.

Queue and status are shared through `~/Library/Application Support/ProToolsIndicator/status.json`; a lock file serializes concurrent CLI updates. All commands must run as the same macOS user as the menu bar app. The build script creates an app bundle and a CLI binary under `dist/`. Add `dist/bin` to the agent's `PATH` or call the binary by its full path.
