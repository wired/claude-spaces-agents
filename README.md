# claude-spaces-agents

A tmux picker for Claude Code background sessions (`claude --bg`, `claude agents`). Sibling of
[claude-spaces](https://github.com/wired/claude-spaces).

Claude keeps background sessions running on its own. This tool is a view of them: a side panel
listing the sessions of the current project, one pane that shows whichever you pick, and one
terminal per session. Closing the view stops no session.

```
+------------------------------------+------------------------------+
|                                    | ~wired/project               |
|  the session you picked            | 1 Fix the login bug       5m |
|  (claude attach), or the           | 2 Refactor the parser      … |
|  welcome screen                    | 3 Old one (failed)        1d |
|                                    |                              |
+------------------------------------+      ─ other projects ─      |
|                                    | webapp                       |
|  that session's terminal           | 4 camera firmware         3h |
|                                    |                              |
|                                    | : menu  / search             |
|                                    | Q:detach  ?:help             |
|                                    |                              |
|                                    | spaces-agents v…             |
+------------------------------------+------------------------------+
        client pane and terminal        picker (30 columns by default)
```

## Status

A prototype. It depends on agent view, which is a research preview in Claude Code, so Claude's
side of it may change. It has been run against Claude Code 2.1.325 only, and refuses to start
on anything older.

This is a hobby project and Claude wrote most of the code. Try it before trusting it with work
that matters.

What it does to your sessions:

- It reads the session list from `claude agents --json`, and the tail of each session's
  transcript for its last activity. It writes only to its own directories.
- Stop and Remove run `claude stop` and `claude rm`, after asking.
- A session you started from the picker and never typed into is removed when you move on to
  another one.

## Install

```
make install                    # /usr/local/bin (may need sudo)
PREFIX=~/.local make install    # ~/.local/bin
make dev                        # symlink this checkout into ~/.local/bin
```

Requires bash 4.4+, tmux 3.0+, jq, and Claude Code 2.1.325 or newer.

## Quick start

```
claude-spaces-agents              # launch
claude-spaces-agents --restart    # close the view and start it again
claude-spaces-agents --reset      # close the view and clear its state
claude-spaces-agents --help
```

Run it from a project directory. Each project gets its own tmux server. Projects that have
background sessions of their own are listed under "other projects"; selecting one, or one of
its sessions, switches to that project's view.

## Keys

`claude-spaces-agents --help` lists them all. The main ones:

| Key | What it does |
|---|---|
| `Enter`, `Space` | show the session (`Enter` also moves focus to it) |
| prefix `c`, or `:c` | new background session in this project |
| prefix `x`, or `:x` | stop the session |
| prefix `D`, or `:D` | remove the session (stops its work) |
| prefix `v`, or `:v` | agent view, where `/resume` brings back older conversations |
| prefix `` ` `` | the session's terminal: open it, then switch focus |
| prefix `Tab`, `q`, `t` | terminal to the side, to the bottom, on and off |
| prefix `s`, or `:s` | close the view; sessions keep running, terminals do not |

Pressed from the Claude pane, stop and remove act on the session you are looking at. In a
session, the left arrow on an empty prompt opens agent view; the picker follows what you open
there.

## Configuration

`~/.config/claude-spaces-agents/config`, created on first run with every key commented out. The
keys are those of claude-spaces, plus `poll_interval`: the seconds between refreshes of the
session list.

## Relation to claude-spaces

The script was forked from claude-spaces at commit `bd12ce2` (0.9.12-dev). The two can run on
the same project. [SPEC.md](SPEC.md) is the design: what changed from claude-spaces, why, and
what was measured against Claude Code.

## Tests

```
make test      # every test, about a minute
make breaks    # proves each test can fail, about ten minutes
```

The tests use a real tmux server and a fake `claude`; no real session is started. `run_breaks`
damages a copy of the script one small piece at a time and expects the tests named for that
piece to fail.

## License

MIT
