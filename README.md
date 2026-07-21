# wakeroad

Keep your Mac awake while files are being written under directories you watch,
so a long unattended job doesn't stall when the machine idle-sleeps. `wakeroad`
notices writes under the trees you watch and keeps the machine awake, then lets
it sleep again once things have been quiet for a while (5 minutes by default).
Its flagship use is keeping the machine up while an AI coding agent (Claude
Code, Codex) works — those two are set up out of the box — but you can point it
at any directory tree and file type, with nothing to configure on the watched
side.

WakeRoad comes in two flavors sharing the same core: a menu bar app
(`WakeRoad.app`) and a command-line tool (`wakeroad`, see [CLI](#cli)).

## How it works

- You define **watch targets**: a directory tree plus the file extensions that
  count as activity there. Out of the box these are the AI coding agents'
  transcripts (`~/.claude/projects/**/*.jsonl`,
  `~/.codex/sessions/**/*.jsonl`), and you can add, edit, or remove your own.
- All targets share a single FSEvents stream. A matching write tells macOS not
  to idle-sleep (the display may still turn off; an option keeps it on too);
  after the configured timeout with no matching writes, the machine may sleep.
- On startup it scans for the most recent write across the targets and starts
  active if it lands within the timeout window, so a task already running is
  picked up.
- Sleep inhibition is released on quit, and macOS releases it automatically if
  the process dies, so a crash never leaves sleep inhibited.

## Example: keeping AI coding agents awake

The reason wakeroad exists is the long agent session: you start one, walk away,
and don't want the Mac to sleep and stall it halfway through. Agents append to
their transcript files in real time, so a transcript write is a good "the agent
is doing something" signal — and watching those files needs no cooperation from
the agent. That is the deliberate trade-off: rather than [Claude Code
hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) that fire exactly
when the agent starts and stops (precise, but you install and maintain them),
wakeroad observes from the outside with zero configuration, at some cost in
accuracy (see [Limitations](#limitations)). If you want exact tracking and don't
mind hooks, a hooks-based tool will serve you better; if you want something that
just works — including with Codex, or future versions whose hooks you haven't
set up — that's what wakeroad is for.

## Requirements

- macOS 13+
- Swift toolchain (to build from source)

## Install

The `wakeroad` [CLI](#cli) ships inside the app bundle, so either of the
prebuilt options below gives you both.

### Homebrew

```sh
brew install --cask dayflower/tap/wakeroad
```

The cask installs the menu bar app and links the CLI onto your PATH.

### Download from Releases

Download the zip from
[Releases](https://github.com/dayflower/wakeroad/releases) and move
`WakeRoad.app` into `/Applications`. To use the bundled CLI, link it onto your
PATH:

```sh
ln -s /Applications/WakeRoad.app/Contents/Helpers/wakeroad /usr/local/bin/wakeroad
```

### Build from source

```console
$ ./scripts/make-app.sh
$ cp -R dist/WakeRoad.app /Applications/
```

The bundle is ad-hoc signed, which is enough to run on the machine that built
it. Set `CODESIGN_IDENTITY` to a Developer ID Application identity to sign it
for real instead. "Launch at Login" uses `SMAppService`, which only works
when the app is launched from a proper `.app` bundle — run it from
`/Applications` (or wherever you copied it), not via `swift run WakeRoadApp`.

For the CLI on its own, no bundle is needed:

```console
$ swift build -c release
$ cp .build/release/wakeroad /usr/local/bin/   # or anywhere on your PATH
```

## Menu bar app

The menu bar app runs the watcher in the background with no terminal
required. Claude Code and Codex are already configured as watch targets on first
launch, so it does something useful immediately — and you can add your own trees
in **Settings** (see below). The icon shows the current state (bolt filled while
sleep is inhibited), and the menu lets you:

- Pause / resume watching (pausing lets the machine sleep immediately)
- Change the idle timeout (1 / 5 / 15 / 30 min)
- Toggle "Keep Display Awake"
- Toggle "Launch at Login"
- Open **Settings…** to manage watch targets

### Settings

Basic settings (idle timeout, keep display awake, launch at login) live in the
menu bar dropdown. Choose **Settings…** to open a window for **watch targets**:
directory trees, each with its own file extensions and a display name. The
default Claude Code and Codex entries appear here too, so you can edit or remove
them like any other target. Adding, editing, or removing a target takes effect
immediately — no restart needed.

A target with no extensions, or whose directory does not exist, is ignored.
Settings are stored in `UserDefaults` under the `com.github.dayflower.wakeroad`
domain; a legacy `extraWatchRoots` array (if present) is migrated into watch
targets automatically on first launch.

## CLI

If you prefer a terminal, the same watcher is available as a foreground
command-line tool. It comes with the app — see [Install](#install).

### Usage

```console
$ wakeroad run [options]
```

| Option | Description |
|---|---|
| `--timeout <sec>` | Seconds without writes before the machine may sleep again (default: 300) |
| `--display` | Also prevent the display from sleeping |
| `--watch <path[=ext,ext]>` | Additional directory tree to watch (repeatable). Append `=ext,ext` for specific extensions, e.g. `~/proj=md,log`; otherwise transcript extensions (`jsonl`) are used |
| `--config <path>` | JSON config file listing watch targets (see below) |
| `--verbose` | Log every matching file event |

`run` is the default subcommand, so plain `wakeroad` works too.
The tool runs in the foreground; stop it with Ctrl-C.

#### Config file

Instead of repeating `--watch` flags, list watch targets in a JSON file. It is
read from `~/.config/wakeroad/config.json` when present, or from the path given
to `--config`. This file is specific to the CLI; it is not shared with the menu
bar app's settings.

```json
{
  "watchTargets": [
    { "name": "Notes", "path": "~/notes", "extensions": ["md", "txt"] },
    { "path": "~/logs", "extensions": ["log"] }
  ]
}
```

**With no config file, Claude Code and Codex are watched by default.** When a
config file is present it becomes the authoritative list: the built-in agents
are no longer added automatically, so the file watches exactly what you list
(plus any `--watch` flags, which always apply). To keep watching the agents
alongside your own targets, add them explicitly:

```json
{
  "watchTargets": [
    { "name": "Claude Code", "path": "~/.claude/projects", "extensions": ["jsonl"] },
    { "name": "Codex", "path": "~/.codex/sessions", "extensions": ["jsonl"] },
    { "name": "Notes", "path": "~/notes", "extensions": ["md"] }
  ]
}
```

`name` is optional (it defaults to the directory name). A target whose directory
does not exist is skipped. Passing `--config` with a missing or malformed file
is an error; the default path is silently ignored when absent.

You can check whether sleep is currently inhibited with:

```console
$ pmset -g assertions | grep wakeroad
```

Running the CLI and the menu bar app at the same time is harmless: each holds
its own sleep inhibition independently while active.

## Limitations

- **Closing the lid still puts the machine to sleep.** wakeroad only prevents
  *idle* sleep; clamshell sleep cannot be inhibited this way.
- Activity detection is write-based: wakeroad only sees writes, not whether
  useful work is happening. For an AI agent deep in one long response, quiet
  gaps of tens of seconds to a few minutes can pass with no writes, which look
  idle. The default 5-minute timeout absorbs these — which also means the
  machine stays awake that long after a session actually ends.
- A watch target whose directory does not exist yet is skipped, and a directory
  created after startup is not picked up until the target list is next resolved
  (on restart, or — in the menu bar app — when you edit the targets).
- The default targets' transcript paths are internal details of Claude Code /
  Codex and may change in future versions. If that happens the only effect is
  that sleep is no longer inhibited for them; point a custom target at the new
  location to restore it.
