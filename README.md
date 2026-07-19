# wakeroad

Keep your Mac awake while AI coding agents (Claude Code, Codex) are working.

You kick off a long agent session, step away for coffee, and come back to find
your Mac asleep and the agent stalled. `wakeroad` fixes that: it notices when
an agent is actively working and keeps the machine awake, then lets it sleep
again once the agent has been quiet for a while (5 minutes by default).

No setup on the agent side is required — no hooks, no notify scripts, no
config changes. Install it, run it, and forget about it.

WakeRoad comes in two flavors sharing the same core: a menu bar app
(`WakeRoad.app`) and a command-line tool (`wakeroad`, see [CLI](#cli)).

## How it works

- Watches the following directory trees with a single FSEvents stream:
  - Claude Code: `~/.claude/projects/**/*.jsonl`
  - Codex: `~/.codex/sessions/**/*.jsonl`
- These are the transcript files the agents append to in real time during a
  session, so a write means the agent is working. On a write, wakeroad tells
  macOS not to idle-sleep (the display may still turn off; there is an option
  to keep it on too).
- After the configured timeout with no writes, the machine may sleep again.
- On startup, it scans for the most recently modified transcript and starts in
  the active state if it was written within the timeout window, so sessions
  already running are picked up.
- The sleep inhibition is released on quit, and macOS automatically releases
  it if the process dies, so a crash never leaves sleep inhibited.

## No hooks required

Claude Code offers [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks)
that fire exactly when the agent starts and stops working, and a tool built on
them can track agent activity precisely. wakeroad deliberately takes the other
trade-off: it never touches your agent configuration and instead just observes
transcript files from the outside, at the cost of some accuracy.

Concretely, wakeroad only sees transcript writes. While the agent is deep in
one long response, quiet gaps of tens of seconds to a few minutes can pass
with no writes at all — wakeroad cannot tell "still thinking" from "done".
The default 5-minute timeout exists to absorb these gaps, and it also means
the machine stays awake for that long after a session actually ends.

If you want exact tracking and don't mind installing hooks, a hooks-based
tool will serve you better. If you want something that works with zero agent
configuration — including with agents like Codex, or future versions whose
hook support you haven't set up — that's what wakeroad is for.

## Requirements

- macOS 13+
- Swift toolchain (to build)

## Menu bar app

The menu bar app runs the watcher in the background with no terminal
required. The icon shows the current state (bolt filled while sleep is
inhibited), and the menu lets you:

- Pause / resume watching (pausing lets the machine sleep immediately)
- Change the idle timeout (1 / 5 / 15 / 30 min)
- Toggle "Keep Display Awake"
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
directories (the CLI's `--watch` equivalent) yet, but you can set them
directly:

```console
$ defaults write com.github.dayflower.wakeroad extraWatchRoots -array ~/some/dir
```

The change takes effect the next time the app starts.

## CLI

If you prefer a terminal, the same watcher is available as a foreground
command-line tool.

### Build

```console
$ swift build -c release
$ cp .build/release/wakeroad /usr/local/bin/   # or anywhere on your PATH
```

### Usage

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

You can check whether sleep is currently inhibited with:

```console
$ pmset -g assertions | grep wakeroad
```

Running the CLI and the menu bar app at the same time is harmless: each holds
its own sleep inhibition independently while active.

## Limitations

- **Closing the lid still puts the machine to sleep.** wakeroad only prevents
  *idle* sleep; clamshell sleep cannot be inhibited this way.
- Activity detection is write-based, so long quiet stretches within a single
  agent response are invisible (see [No hooks required](#no-hooks-required));
  the default 5-minute timeout is chosen to absorb these.
- If `~/.codex` (or another watch root) is created after startup, it is not
  picked up until wakeroad is restarted.
- The transcript paths are internal details of Claude Code / Codex and may
  change in future versions. If that happens the only effect is that sleep is
  no longer inhibited.
