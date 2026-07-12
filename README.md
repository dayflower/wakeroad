# wakeroad

Prevent macOS from sleeping while AI coding agents (Claude Code, Codex) are working.

`wakeroad` watches the transcript files that Claude Code and Codex append to in
real time during a session, and holds an IOKit power assertion while writes are
happening. When no transcript has been written for a configurable timeout
(default 5 minutes), the assertion is released and the machine may sleep again.

No configuration on the agent side (hooks, notify scripts, etc.) is required —
`wakeroad` works standalone, purely by observing file activity.

It comes in two flavors sharing the same core: a foreground CLI (`wakeroad`)
and a menu bar app (`WakeRoad.app`, see [Menu bar app](#menu-bar-app-gui)).

## How it works

- Watches the following directory trees with a single FSEvents stream:
  - Claude Code: `~/.claude/projects/**/*.jsonl`
  - Codex: `~/.codex/sessions/**/*.jsonl`
- On a `.jsonl` write, acquires a `PreventUserIdleSystemSleep` power assertion
  (the display may still turn off; use `--display` to keep it on too).
- Releases the assertion after `--timeout` seconds without writes.
- On startup, scans for the most recently modified transcript and starts in
  the active state if it was written within the timeout window, so sessions
  already running are picked up.
- The assertion is released on SIGINT/SIGTERM, and the kernel automatically
  releases it if the process dies, so a crash never leaves sleep inhibited.

## Requirements

- macOS 13+
- Swift toolchain (to build)

## Build

```console
$ swift build -c release
$ cp .build/release/wakeroad /usr/local/bin/   # or anywhere on your PATH
```

## Usage

```console
$ wakeroad run [options]
```

| Option | Description |
|---|---|
| `--timeout <sec>` | Seconds without writes before the machine may sleep again (default: 300) |
| `--display` | Also prevent the display from sleeping |
| `--watch <path>` | Additional directory tree to watch (repeatable) |
| `--verbose` | Log every matching file event |

`run` is the default subcommand, so plain `wakeroad` works too.
The tool runs in the foreground; stop it with Ctrl-C.

You can check the assertion state at any time with:

```console
$ pmset -g assertions | grep wakeroad
```

## Menu bar app (GUI)

WakeRoad also ships as a menu bar app that runs the same watcher in the
background, with no terminal required. The icon shows the current state
(bolt filled while sleep is inhibited), and the menu lets you:

- Pause / resume watching (pausing releases the assertion immediately)
- Change the idle timeout (1 / 5 / 15 / 30 min)
- Toggle "Keep Display Awake" (the `--display` equivalent)
- Toggle "Launch at Login"

### Build and install

```console
$ ./scripts/make-app.sh
$ cp -R dist/WakeRoad.app /Applications/
```

The bundle is ad-hoc signed; it is meant for building on your own machine,
not for distribution. "Launch at Login" uses `SMAppService`, which only works
when the app is launched from a proper `.app` bundle — run it from
`/Applications` (or wherever you copied it), not via `swift run WakeRoadApp`.

### Settings

Settings are stored in `UserDefaults` under the
`com.github.dayflower.wakeroad` domain. There is no UI for additional watch
directories (the `--watch` equivalent) yet, but you can set them directly:

```console
$ defaults write com.github.dayflower.wakeroad extraWatchRoots -array ~/some/dir
```

The change takes effect the next time the app starts.

Running the CLI and the GUI at the same time is harmless: assertions are
per-process, so both simply hold one while active.

## Limitations

- **Closing the lid still puts the machine to sleep.** Power assertions only
  prevent *idle* sleep; clamshell sleep cannot be inhibited this way.
- Transcript writes are event-based. During one long LLM response there can be
  quiet gaps of tens of seconds to a few minutes with no writes; the default
  5-minute timeout is chosen to absorb these.
- If `~/.codex` (or another watch root) is created after startup, it is not
  picked up until `wakeroad` is restarted.
- The transcript paths are internal details of Claude Code / Codex and may
  change in future versions. If that happens the only effect is that sleep is
  no longer inhibited.
