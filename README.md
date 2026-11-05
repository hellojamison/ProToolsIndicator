# Pro Tools Indicator

A tiny macOS menu bar light that agents can control with `pt-indicator`. Green means available; amber means one or more Pro Tools apps are open; red means someone holds the Pro Tools turn. Requests are granted in FIFO order. The app detects open Pro Tools application versions but does not inspect sessions or control Pro Tools.

## Build and run

Requires macOS 13 or later and Swift 6.

```sh
./scripts/build-app.sh
open dist/ProToolsIndicator.app
```

In another terminal, request access and identify the agent plus the exact current chat title:

```sh
./dist/bin/pt-indicator request --minutes 5 "Claude: Improve menu bar icon"
./dist/bin/pt-indicator status
```

The optional `--minutes` value is the agent's expected Pro Tools work duration. Waiting requests are ordered shortest estimate first; ties stay FIFO, and requests without an estimate follow estimated requests. When a request is granted, the same value starts as that agent's ETA. Update it while working with `pt-indicator eta <ticket> <minutes|unknown>`; the ETA is a self-reported estimate, not a countdown or time limit.

If Pro Tools is busy, `request` adds the caller to the queue and prints its ticket and position. `wait <ticket>` blocks until the turn is granted. `status` shows the current agent and their reported remaining-time ETA, plus each queued agent's projected start ETA and expected work duration. Queue ETAs are projections from agent estimates, not guarantees. Release requires a closeout report, for example `release <ticket> --closeout saved-and-closed`; the report is saved and shown in `status` so the next person can see whether the session was saved and closed. The available closeout values are `no-session`, `saved-and-closed`, `no-save-needed-and-closed`, `left-open-needs-save`, and `left-open-no-save-needed`. Save needed work and close sessions you opened when finished. Preserve someone else's session or unsaved work; if a session cannot safely be closed, report the matching left-open state. `cancel <ticket>` removes a waiting request. The menu bar popover shows the current agent, their ETA, the waiting queue, and open Pro Tools versions. It lets the local user remove waiting entries or release to the next person with the same closeout report. An open app is shown separately from a reservation, so the queue can hand Pro Tools to an agent using an already-open session.

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
# Save if needed, close sessions you opened, then report the truthful closeout:
./dist/bin/pt-indicator release "$ticket" --closeout saved-and-closed
```

Choose the closeout value that matches what actually happened. If a command is interrupted while queued, cancel that waiting ticket. Never use a cleanup trap that releases an active turn without first reporting the session state.

Queue and status are shared through `~/Library/Application Support/ProToolsIndicator/status.json`; a lock file serializes concurrent CLI updates. All commands must run as the same macOS user as the menu bar app. The build script creates an app bundle and a CLI binary under `dist/`. Add `dist/bin` to the agent's `PATH` or call the binary by its full path.
