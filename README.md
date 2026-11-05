# Pro Tools Indicator

A tiny macOS menu bar light that agents can control with `pt-indicator`. Green means available; red means someone holds the Pro Tools turn. Requests are granted in FIFO order, and the app does not inspect or control Pro Tools automatically.

## Build and run

Requires macOS 13 or later and Swift 6.

```sh
./scripts/build-app.sh
open dist/ProToolsIndicator.app
```

In another terminal, request access and identify the person or agent:

```sh
./dist/bin/pt-indicator request --minutes 5 "Claude"
./dist/bin/pt-indicator status
```

The minutes estimate is optional and means expected Pro Tools usage duration. Waiting requests are ordered shortest estimate first; ties stay FIFO, and requests without an estimate follow estimated requests. Estimates only affect waiting order: they do not interrupt a current user or enforce a time limit, so long tasks can wait behind shorter ones.

If Pro Tools is busy, `request` adds the caller to the queue and prints its ticket and position. `wait <ticket>` blocks until the turn is granted; `release <ticket>` releases the turn and automatically hands Pro Tools to the next queued caller. `cancel <ticket>` removes a waiting request, and `status` shows the current user and full queue with estimates. The menu bar popover shows the queue and lets the local user remove waiting entries or release to the next person.

For scripts, request a ticket, wait if queued, and release the ticket in a cleanup trap:

```sh
set -e
reservation=$(./dist/bin/pt-indicator request --minutes 5 "Claude")
ticket=${reservation##*ticket=}
cleanup() {
  ./dist/bin/pt-indicator release "$ticket" >/dev/null 2>&1 \
    || ./dist/bin/pt-indicator cancel "$ticket" >/dev/null 2>&1 \
    || true
}
trap cleanup EXIT
case "$reservation" in
  queued*) ./dist/bin/pt-indicator wait "$ticket" ;;
esac
# Agent work that uses Pro Tools
```

Queue and status are shared through `~/Library/Application Support/ProToolsIndicator/status.json`; a lock file serializes concurrent CLI updates. All commands must run as the same macOS user as the menu bar app. The build script creates an app bundle and a CLI binary under `dist/`. Add `dist/bin` to the agent's `PATH` or call the binary by its full path.
