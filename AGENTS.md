# AGENTS.md

## What this project is

`wakeroad` keeps macOS awake while files are written under directory trees you
watch. It ships as two executables sharing one core library:

- `WakeRoadApp` — SwiftUI `MenuBarExtra` menu bar app, distributed as
  `WakeRoad.app`.
- `wakeroad` — foreground CLI (swift-argument-parser), bundled inside the app at
  `Contents/Helpers/wakeroad`.

See [README.md](README.md) for user-facing behavior and options.

## Commands

```sh
make build     # swift build -c release
make test      # swift test
make format    # swift-format --in-place (Sources + Tests)
make check     # swift-format lint --strict  (CI runs this first)
make app       # assemble dist/WakeRoad.app via scripts/make-app.sh
make install   # make app + copy to /Applications
```

`swift build` / `swift test` work directly too. Always run `make check` (or
`make format`) before committing — CI fails on lint. `swift-format` ships with
Xcode 16+; config is in [.swift-format](.swift-format) (4-space indent).

`make app` requires a full Xcode (not just Command Line Tools) because `actool`
compiles the Icon Composer document in [icons/wakeroad.icon/](icons/wakeroad.icon/).

## Layout

| Path | Role |
|---|---|
| [Sources/WakeRoadCore/](Sources/WakeRoadCore/) | All logic. Platform-agnostic of UI; the only tested target |
| [Sources/wakeroad/](Sources/wakeroad/) | CLI entry point, argument parsing, stdout logging |
| [Sources/WakeRoadApp/](Sources/WakeRoadApp/) | SwiftUI menu bar app, `UserDefaults` settings, `os.Logger` |
| [Tests/WakeRoadCoreTests/](Tests/WakeRoadCoreTests/) | XCTest suite for the core |
| [scripts/](scripts/) | Bundle assembly, notarization, version bump |

## Architecture

The data flow is one direction:

```
WatchTarget(s) → FileActivityWatcher (FSEvents) → ActivityMonitor (state machine)
                                                        → SleepInhibitor (IOKit assertion)
```

- **`WatchTarget`** is the single resolved shape everything downstream deals
  with: absolute existing root + extension set. Built-in agents
  ([`Agent.known`](Sources/WakeRoadCore/Agent.swift)), GUI `CustomWatchTarget`s,
  CLI `--watch` specs, and `CLIConfig` entries all funnel through
  [`WatchRoots`](Sources/WakeRoadCore/WatchRoots.swift) to become `WatchTarget`s.
- **`WakeRoadSession`** ([WakeRoadSession.swift](Sources/WakeRoadCore/WakeRoadSession.swift))
  is the only thing entry points touch. It owns the queue, watcher, monitor, and
  inhibitor as a unit.
- **`ActivityMonitor`** is a pure state machine (idle/active) driven by writes
  and a 10s idle-check timer. It takes an injected clock (`now`) and a
  `SleepInhibiting` protocol so tests need neither real time nor IOKit.
- Supporting a new AI agent means adding one entry to `Agent.known` — roots,
  file filters, and display names all derive from it.

### Conventions to preserve

- **Threading:** every `ActivityMonitor` / `SleepInhibitor` call happens on the
  session's serial queue. Both are `@unchecked Sendable` precisely because that
  rule is enforced by `WakeRoadSession`, not by internal locking. Don't call
  them from elsewhere. `AppController` is `@MainActor` and hops via `Task`.
- **Logging** is injected as a `LogHandler` closure — core code never prints.
  The CLI formats to stdout; the app forwards to `os.Logger`.
- **Comments explain *why*, not *what*.** The existing code is deliberately
  commented at decision points (why `Contents/Helpers`, why the config file is
  authoritative, why canonicalized paths). Match that density; don't add
  narration of obvious code.
- CLI config (`~/.config/wakeroad/config.json`) and GUI settings (`UserDefaults`
  under `com.github.dayflower.wakeroad`) are intentionally **not** shared.

## Testing

Only `WakeRoadCore` is tested; the CLI and SwiftUI layers are kept thin enough
not to need it. Tests use fakes rather than the real system:
`FakeInhibitor`/`FakeClock` for the monitor, a scratch `UserDefaults` suite for
`CustomWatchTargetStore`, temp directories for path resolution. Keep new core
logic testable the same way — inject the dependency instead of reaching for
`Date()`, IOKit, or `.standard`.

## Release flow

Do not tag or edit versions by hand.

1. `scripts/bump-version.sh <version|patch|minor|major>` — bumps
   `Resources/Info.plist` on a branch and opens a PR.
2. Merging to `main` triggers [.github/workflows/release.yml](.github/workflows/release.yml):
   it detects the version change, builds, signs with Developer ID, notarizes,
   staples, publishes the GitHub Release tagged `v<version>`, and updates the
   Homebrew cask.

## Conventions

- Code, comments, documentation, commit messages, and PR/issue text: **English**.
- Commits: conventional commits without a scope (`fix: ...`, not `fix(core): ...`),
  subject line only, then a blank line and `Co-Authored-By`.
- Update [README.md](README.md) when user-visible behavior, CLI options, or
  settings change.
