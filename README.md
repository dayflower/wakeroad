# wakeroad

Prevent macOS from sleeping while AI coding agents (Claude Code, Codex) are working.

`wakeroad` watches the transcript files that Claude Code and Codex append to in
real time during a session, and holds an IOKit power assertion while writes are
happening. When no transcript has been written for a configurable timeout
(default 5 minutes), the assertion is released and the machine may sleep again.

No configuration on the agent side (hooks, notify scripts, etc.) is required —
`wakeroad` works standalone, purely by observing file activity.

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
