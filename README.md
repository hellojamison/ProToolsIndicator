# Pro Tools Indicator

A tiny macOS menu bar light that agents can control with `pt-indicator`. Green means available; red means an agent has marked Pro Tools in use. The app does not inspect or control Pro Tools automatically.

## Build and run

Requires macOS 13 or later and Swift 6.

```sh
./scripts/build-app.sh
open dist/ProToolsIndicator.app
```

In another terminal, control the light:

```sh
./dist/bin/pt-indicator on
./dist/bin/pt-indicator status
./dist/bin/pt-indicator off
```

The menu bar app also provides “Mark In Use” and “Mark Available.” State is shared through `~/Library/Application Support/ProToolsIndicator/status.json`, so the CLI can be called from any agent script on the same Mac. For scripts, pair `on` with `off` in a cleanup trap so the indicator resets if the work exits early:

```sh
./dist/bin/pt-indicator on
trap './dist/bin/pt-indicator off' EXIT
# Agent work that uses Pro Tools
```

The build script creates an app bundle and a CLI binary under `dist/`. Add `dist/bin` to the agent's `PATH` or call the binary by its full path.
