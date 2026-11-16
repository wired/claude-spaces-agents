# CLAUDE.md

## What is this

claude-spaces-agents is a single-file bash script: a tmux picker for Claude Code background
sessions (`claude --bg`, `claude agents`). Claude's supervisor owns the sessions. The script
owns only a view of them.

It was forked from claude-spaces (`github.com/wired/claude-spaces`) at commit `bd12ce2`
(0.9.12-dev).

`SPEC.md` is the design and the authority. Read its "Things that are easy to break" before
changing switching, following, terminals or polling.

## Files

- `claude-spaces-agents` — the entire tool
- `run_tests` — tests (evals the function definitions up to the `# ── Entrypoint` marker; Claude is a fake `claude` on PATH)
- `run_breaks` — proves each test can fail (see Testing)
- `SPEC.md` — the specification
- `Makefile` — `make install`, `make dev` (symlink), `make test`, `make breaks`

## Architecture in short

- **Dual-mode self-re-exec**, controlled by `CS_PICKER` and `CS_STATE_DIR`: the launcher
  (`cs_launch`) creates or attaches to the tmux server; the picker (`cs_picker_loop`) is the
  TUI. `R` re-execs the picker in place.
- **One tmux server per project**, named by `cs_server_name` (`csa-…`). All tmux calls go
  through `_tmux`. The prefix must never start with `cs-`: claude-spaces finds its own servers
  by globbing sockets named `cs-*`.
- **One client pane**, respawned on every switch, only through `cs_client_respawn` and
  `cs_switch_chain`. Each respawn sets a marker title in the same tmux call.
- **`displayed` and `shown`** are two values: the session whose terminal layout the window has,
  and what the client pane shows right now.
- **Terminals** are keyed by job id. The displayed session's terminal is in the main window;
  the rest are parked in hidden windows pinned to their own size.
- **The session list** comes from `claude agents --json --all`. Its values are validated
  (`ID_RE`, `UUID_RE`) before they reach a command line.
- **The state dir is ephemeral** and is wiped when the recorded picker pane is dead.
  `CS_COMPAT_VERSION` is bumped for any change a running server cannot survive.

## Testing

```
make test                  # lint, then every test (about a minute)
./run_tests <test_name>    # one test, no lint
make breaks                # every break (about ten minutes)
./run_breaks <word>        # the breaks whose label or tests contain <word>
```

- The tests need a real tmux. Nothing is mocked at the tmux level.
- After every test a check looks at the panes, windows and state files that are left.
- **Every test has a break.** `run_breaks` lists lines of the script to damage and the tests
  that must go red. It reports a test that stays green, a break whose lines are no longer in
  the script, and a test no break names. A new or changed test is not done until its break has
  been seen red.

## Conventions

- Functions are prefixed `cs_` and globals `CS_`, as in claude-spaces, so fixes port between
  the two scripts
- `_tmux` for all tmux calls (never bare `tmux`)
- Indent 2 spaces
- Bash 4.4+ (associative arrays, namerefs, `${var@Q}`)
- Config in `${XDG_CONFIG_HOME:-~/.config}/claude-spaces-agents/config`; data (project names,
  `seen/`) in `${XDG_DATA_HOME:-~/.local/share}/claude-spaces-agents/`
- Claude is reached through its CLI only. The one exception is the tail of a session's
  transcript, for its last activity. Never read `~/.claude/jobs/`, `sessions/` or `daemon/`.

## Versioning

The version is in two places, both in the script: the header comment and `VERSION=`. The README
carries none on purpose. Strategy as in claude-spaces: bump-on-open, default patch. There is no
release target yet. `git log` is the changelog.

## Documentation

When keys, config keys or user-facing behaviour change, update `cs_help_text`, the default
config text in the script, `README.md` and `SPEC.md` to match.

## Porting from claude-spaces

In a claude-spaces checkout, `git diff bd12ce2.. -- claude-spaces` shows what changed there
since the fork.
