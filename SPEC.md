# claude-spaces-agents

A tmux picker for Claude Code **background sessions** ("agents"). Sibling of claude-spaces.

Status: prototype. Implemented in `claude-spaces-agents`, tested by `run_tests` and
`run_breaks` (§ Testing). Developed against Claude Code 2.1.325, where agent view is a
research preview ("The interface and keyboard shortcuts may change").

The script was forked from claude-spaces (`github.com/wired/claude-spaces`) at commit `bd12ce2`
(0.9.12-dev). Wherever this spec says "as in claude-spaces" or "unchanged from claude-spaces",
that commit is the reference.

## The shift

In claude-spaces a tmux pane keeps each Claude alive, so the picker owns processes: one window per
session, fillers, `panes/<num>`, bell hooks.

With `claude --bg`, Claude's supervisor owns the processes. claude-spaces-agents owns only a
**view**: a picker pane, one client pane, and per-session terminal panes. Killing the tmux server
loses no session. It does kill the terminals and whatever runs in them.

## Decisions

| Decision | Why |
|---|---|
| Separate script `claude-spaces-agents`, forked from claude-spaces | The change replaces the core layers (pane lifecycle, discovery, bells), not the edges. A mode flag would branch all of them and double the test matrix. It also keeps a research-preview dependency out of claude-spaces. |
| Its own repository | The two tools have separate versions, and tags belong to a repository, not to a script. In one repository every claude-spaces release tarball would also carry this script. Functions keep the `cs_` prefix and variables `CS_`, so fixes port between the two scripts by hand. || Agents-only list | Source of truth is `claude agents --json --all`, background entries only. Interactive sessions are not listed. No transcript scan, no name resolution, no hidden list. Older conversations are reached with `/resume` in agent view. |
| One tmux server per project | Same as claude-spaces: launcher, server naming and state layout carry over, new sessions start in `$PWD`, and two terminals on two projects stay independent. A single global server would mirror every attached terminal. |
| One client pane per server | The pane runs `claude attach <id>`; switching respawns it. No per-session Claude windows and no picker fillers. |
| `←` stays enabled | It cannot be disabled for an attached client without disabling the feature. The picker follows what the client shows instead. |
| Claude's default worktree isolation is supported | Sessions under `<project>/.claude/worktrees/` belong to `<project>`. Removal goes through `claude rm`, which deletes the worktree when safe. With isolation on, a session that finishes commits, pushes its own branch and opens a draft pull request without asking. `worktree.bgIsolation: none` turns isolation off. |

## Claude interface

Only the CLI, with one exception: the picker reads record types and timestamps from the tail of
a session's transcript, for its last-activity time (§ Last activity). Never read
`~/.claude/jobs/`, `~/.claude/sessions/` or `~/.claude/daemon/`: the docs say the job files "are
not a stable interface" and recommend `claude agents --json`.

| Command | Use |
|---|---|
| `claude agents --json --all` | The session list (documented polling interface) |
| `claude --bg` (no prompt) | New session. Prints `backgrounded · <id>` and starts `blocked`, waiting for its first prompt |
| `claude attach <id>` | Show a session in the client pane; also restarts a stopped one |
| `claude stop <id>` | Stop; the row and conversation are kept. An idle session stays `done`, without a process |
| `claude rm <id>` | Remove the row and its worktree, when safe. Stops a working session at once, without asking |
| `claude agents` | Agent view, for `/resume` |

Fields of each `--json` entry:

| Field | Present | Meaning |
|---|---|---|
| `cwd`, `kind`, `startedAt` | always | directory, `interactive` or `background`, start time (ms) |
| `id` | background | short ID for `attach`, `stop`, `rm` |
| `state` | background | `working`, `blocked`, `done`, `failed`, `stopped` |
| `pid`, `status` | process alive | `busy`, `waiting`, `idle` |
| `waitingFor` | `status: waiting` | `permission prompt`, `input needed`, `sandbox request`, `worker request`, `dialog open` |
| `sessionId`, `name` | when set | full UUID; display name |

- Only `kind: background` entries are used. Interactive sessions are ignored everywhere.
- A session is identified by its `id`, and all picker state is keyed by it. `sessionId` is used
  only to find the transcript.
- `id` is eight hex digits, the start of `sessionId`.
- `pid` and `status` are absent when the session has no process. `status` can also be missing for
  a moment while a process starts.
- A session waiting for its first prompt, whether new or a fresh fork, is `blocked` with
  `status: idle` and no `waitingFor`. One waiting on the user is `blocked` with `status: waiting`.
- `name` starts as the prompt text and becomes a generated title during the first turn. A session
  with no prompt yet has its `id` as `name`. A fork keeps its source's name, so duplicate names
  are normal. `name` can also be missing; the row then shows the `id`.
- `startedAt` is when the session's process started. It changes when a stopped session is woken.
- Values from the JSON are not trusted. `id` and `sessionId` are validated against strict
  patterns before use, and every value placed in a command is quoted. `name` never reaches a
  command, and control characters are stripped from it before it is printed.

### Last activity

`--json` has no last-activity time. The picker reads it from the session's transcript. The file
is found by session ID, `~/.claude/projects/*/<sessionId>.jsonl`, and its path is remembered per
`id`. The directory name is not computed: Claude's rule for it is not documented, and a worktree
session's transcript may live somewhere else.

- **Last activity** is the timestamp of the last record of type `user` or `assistant`, or of type
  `system` with subtype `turn_duration`, in the final 256 KB of the file. `turn_duration` marks
  the end of a turn, so for a finished session this is when it finished.
- **The file's mtime is not the time.** Claude appends housekeeping records when a session's
  process stops, when it restarts, and when a client attaches after a while. Most carry no
  timestamp; `away_summary` carries one but is not activity.
- The mtime only says when to read again: the tail is parsed once per change of mtime.
- When no matching record is found in the final 256 KB, the picker reads once more with a larger
  window. If there is still none, the mtime is the fallback, for the age column and the order
  only. Finished, unseen is never raised from an mtime (§ Attention). The list never fails over
  a transcript.
- A session with no transcript uses `startedAt` for order and shows no age. Without a timestamp
  it is never flagged as Finished, unseen (§ Attention). That is the normal state of a session
  with no prompt yet.
- Measured: 5 ms on a 4.8 MB transcript whose longest line was 142 KB.

This reads an internal format, which the docs say changes between versions. claude-spaces
already depends on the same format for session names.

### Environment

`CLAUDE_CODE_DISABLE_AGENT_VIEW=1` disables `claude agents`, `--bg`, `attach` and the supervisor
(`'attach' is disabled by CLAUDE_CODE_DISABLE_AGENT_VIEW.`). `0` and `false` leave them on.

claude-spaces-agents exports `CLAUDE_CODE_DISABLE_AGENT_VIEW=0` at the top of the script, before the
preflight. The launcher, the picker, the tmux server it starts and every pane inherit it, even
when the tool was started from a shell that had `1`.

Companion change in claude-spaces (not part of this tool): set `=1` on the two commands that launch
Claude, so `←` and `/background` cannot move a session out from under its pane. It must be set on
those commands only, never in the claude-spaces server environment.

### Lifetimes are Claude's

- A session idle and unattached for about an hour has its process stopped. Attaching starts a
  fresh one and shows `Session is starting` meanwhile. Only the shown session is attached, so this
  applies to every other session.
- A reboot stops all sessions. They show as `failed`, or `stopped` after 48 hours.
- Conversations are kept in every case.

## Topology

One window: `[client (+ terminal) | picker]`. The picker is `PICKER_WIDTH` wide on the configured
side. A terminal that is not in the main window is parked in a hidden `csa:term` window, pinned to
the size it has when shown (§ Terminals).

The client pane is created once and lives as long as the server. Its ID is stored in
`client_pane`. If it is found dead at startup or on a scan, the picker recreates it with the
welcome screen. It runs one of:

| Content | Command | Pane title |
|---|---|---|
| Welcome | help screen, then `sleep` | the welcome marker |
| Session | `claude attach <id>` | the switching marker; the session's `name` only once it is opened from agent view |
| Agent view | `claude agents` | the agent-view marker, then `claude agents` or `N awaiting input · claude agents` |

**Every respawn of the client pane goes through one helper, which sets a marker title in the same
chain.** That covers switches, the welcome screen and agent view. There are three markers: the
switching marker before a session, the welcome marker before the welcome screen, and the
agent-view marker before agent view (§ Following the client).

Every command is run from the project root and wrapped so the pane never dies:

```
cd <project> && claude attach <id>
rc=$?
<set the pane title to the welcome marker>
((rc)) && exec <sleep>          # leave the client's message on screen
exec <welcome script>
```

- The title is reset first, because tmux keeps a title after the program that set it has exited.
- A client that exits cleanly falls through to the welcome screen.
- A client that fails leaves its message on screen in place of the welcome text, until the next
  switch. Examples: `No job matching …`,
  `Can't open — this session is running in another terminal`.

The project root matters: `/resume` in agent view lists "past sessions of the repository you
opened agent view from".

## Displayed and shown

Two values, kept apart:

| Value | Meaning | Changes |
|---|---|---|
| `displayed` | `id` of the session whose terminal layout the main window has. Empty on the welcome screen. Stored in the state dir. | when the picker switches, adopts a session, or the session goes away |
| `shown` | what the client pane shows right now: a session, or nothing. Not stored. | when the picker switches, and on every scan from the pane title |

- The Focused and Active highlight follows `shown`.
- A switch sets `shown` to the same session as `displayed`. The title cannot do it: after a
  switch it is the switching marker, which leaves `shown` unchanged.
- At startup, which includes a reload, `shown` starts as `displayed` when the title is the
  switching marker. Otherwise it is taken from the title.
- Terminal keys act on `displayed`, also while the client is in agent view. They do nothing when
  `displayed` is empty.
- **The displayed session goes away** on exactly two triggers: its client exits (the title
  becomes the welcome marker), or its `id` leaves the list. A `stopped` state alone is not a
  trigger. The picker then parks its terminal, clears `displayed` and focuses itself. When the
  trigger is the picker's own remove, the terminal is killed instead of parked.
- Agent view is not an exit. Its marker and its own titles leave `displayed` and the terminal
  alone, whether the user got there with `←` or the picker opened it.
- On a client exit the picker does not respawn the client pane. The wrapper has already replaced
  the client, and a respawn would wipe a failed client's message.
- For its own stop or remove of the displayed session, the picker respawns the welcome screen
  first, so no message from the dying client is left on screen.

## Switching

Every switch is one chained `_tmux` call that starts by setting the client pane's title to the
switching marker. Which chain depends on the terminals of the outgoing session (`displayed`) and
the incoming session S. `displayed` and `shown` are set to S after the chain succeeds.

**Neither has a visible terminal** (the common case):

```
_tmux select-pane -t "$CLIENT" -T "$SWITCHING" \;
      respawn-pane -k -t "$CLIENT" "<client command for S>"
```

**Both have one, with the same orientation and size.** The incoming terminal's parking window is
pinned to that size, so the two exchange places without a resize:

```
_tmux select-pane -t "$CLIENT" -T "$SWITCHING" \;
      swap-pane -d -s "$IN_TERM" -t "$OUT_TERM" \;
      respawn-pane -k -t "$CLIENT" "<client command for S>"
```

**Anything else.** The client pane's geometry has to change, so nothing may be attached while it
does:

```
_tmux select-pane -t "$CLIENT" -T "$SWITCHING" \;
      respawn-pane -k -t "$CLIENT" "$PLACEHOLDER" \;           # 1. nothing attached
      swap-pane -d -s "$OUT_TERM" -t "$SLOT" \;                 # 2. outgoing terminal into its slot
      kill-pane -t "$SLOT" \;                                   #    its cell closes
      join-pane -d -s "$IN_TERM" -t "$CLIENT" -l … \;          #    incoming terminal out of its slot
      resize-pane -t "$PICKER" -x "$PICKER_WIDTH" \;            #    the picker keeps its width
      respawn-pane -k -t "$CLIENT" "<client command for S>"     # 3. attach at the final size
```

`$SLOT` is a pinned parking window created just before the chain (§ Terminals). The lines for a
terminal that does not exist are left out. `select-pane -T` only sets the title; it does not move
focus.

The incoming terminal comes back at the size it was parked at, as long as the client area is
still the one it was parked from (§ Parking).

**A switch never changes geometry while a client is attached, and never resizes a terminal.** A
client forwards its size to the session, and a size change makes Claude repaint. Because terminal
state is per session, a session is always attached at the size it was last attached at. Each
switch still costs one client start and one first paint: 180 to 220 ms against live sessions.

Measured on an isolated tmux server, with processes that log every SIGWINCH:

| Switch | Outgoing terminal | Incoming terminal | New client |
|---|---|---|---|
| bottom terminal → side terminal | 0 | 0 | 0 |
| side terminal → bottom terminal | 0 | 0 | 0 |
| bottom → bottom, same size | 0 | 0 | 0 |

When a chain cannot run or fails:

- Before the chain, every pane it names is checked alive. A terminal whose shell has exited is
  forgotten, with its state (§ Terminals): the chain is built as if that session had none. A
  dead client pane is created again first.
- If the chain fails, tmux skips the rest and can leave the placeholder in the client pane. The
  picker then kills `$SLOT` if it still exists, respawns the welcome screen, which parks
  whatever terminal is left in the main window, leaves `displayed` empty, and sweeps leftover
  slots.

Resizing the outer terminal is the exception to the rule. The shown session repaints once, every
other session repaints once at its next attach, and a parked terminal is resized once at its next
show.

Selecting the session that is already shown only focuses the client pane.

## Following the client

`←` on an empty prompt takes the client to agent view, where the user can open any session. The
picker did not cause that switch, so it reads the result.

tmux keeps a pane title across `respawn-pane` and after the program that set it has exited. A
stale title would make the picker adopt the session it has just left. So every respawn of the
client pane sets a marker in the same chain, and the wrapper sets the welcome marker when a
client exits (§ Topology).

The picker turns tmux's `allow-set-title` on at startup. The user's tmux.conf is sourced, and
with that option off tmux would record no title from Claude at all.

The picker already runs `list-panes -a` once per scan cycle. It adds `#{pane_title}` for the
client pane and sets `shown`:

| Title | `shown` |
|---|---|
| the switching marker | unchanged: a switch is in progress |
| the welcome marker | nothing: the welcome screen, or a client that exited |
| the agent-view marker | nothing: agent view is starting |
| `claude agents`, or ends with ` · claude agents` | nothing: agent view |
| equals the `name` of exactly one listed session | that session |
| anything else, or several matches | unchanged |

What sets the title, as measured:

- `claude attach <id>` itself sets no title. After a switch the marker stays, and `shown` keeps
  what the picker set.
- Opening a session from inside agent view sets the title to its `name` at once. A session with
  no prompt yet gets `current session`.
- Agent view sets `claude agents` or `N awaiting input · claude agents`.
- Other strings pass through, such as a terminal capability query that tmux records as a title.
  An unknown title must never be given a meaning.

When `shown` becomes another session of this project, the picker adopts it: `displayed` becomes
that session and the terminals are exchanged in place. That costs the new session one resize,
which is unavoidable because the attach already happened.

A session of another project can be opened this way too. Its row is highlighted in the other
projects section; `displayed` and the terminal stay as they are.

This is a heuristic. Names are not unique (a fork keeps its source's name), a session with no
prompt yet cannot be followed, and the behaviour is undocumented. If it proves unreliable, the
fallback is no following: the highlight can be stale after `←` until the next switch made from
the picker.

## Session list

One unscoped `claude agents --json --all` call feeds every section. Only `kind: background`
entries are listed. `--cwd` is not used for filtering: it is a prefix match, so nested projects
would list each other's sessions.

**Project of an entry**: its `cwd`, with a trailing `/.claude/worktrees/<name>…` removed.

### This project

Entries whose project equals `$PWD`. The first matching row wins:

| Row | Source | Style |
|---|---|---|
| Focused | `shown`, client pane focused | `> ` prefix, bold green |
| Active | `shown`, picker focused | bold green |
| Needs input | `state: blocked` | bell |
| Finished, unseen | `done` or `failed`, and unseen (§ Attention) | bell |
| Working | `state: working` | white, with `…` in the age column |
| Idle | `state: done`, with a process | white |
| No process | any other state, with no `status` | dim; `failed` and `stopped` also get the state as a suffix |

Every row is selectable.

The process is what tells a closed session from an open one. `claude stop` on an idle session
leaves its state `done` and only takes the process away (§ Verified), so a row styled by state
alone does not change when its session is stopped. Claude putting an idle session to sleep after
an hour looks the same, and is the same thing.

Order and the age column work as in claude-spaces, on last activity (§ Last activity). Sessions
active within `recent_threshold` minutes come first, sorted by name. The rest follow, most
recent first; ended sessions always sort there. `startedAt` is not used for order: it is the
process start and moves when a session is woken.

### Attention

Replaces bell detection. No Stop hook and no `alert-bell` hook are needed. The `client-focus-in`
and `client-focus-out` hooks stay: they tell the picker whether the terminal window has focus.

- **Needs input**: `blocked`, for as long as it lasts.
- **Finished, unseen**: the state is `done` or `failed`, and the session's last activity
  (§ Last activity) is newer than the last time it was shown. Only a timestamp read from a
  record counts. The mtime fallback never raises the flag.
- "Last shown" is the mtime of an empty file, `seen/<id>`, in the data dir. The picker touches it
  on every scan in which the session is `shown` and the terminal window has focus, and once more
  when the session stops being shown.
- A session with no `seen` file has never been shown here. It has nothing to compare against and
  is not flagged, however it finished. Flagging those painted every finished session red on a
  first run, and the only way to clear one was to attach to it, which wakes a stopped session.
- Nothing depends on a picker having watched the transition. A session that was shown once and
  finished while the view was closed is flagged when the view comes back. So are sessions of
  other projects, and turns that were started from outside this tool.
- `seen/` is shared by all pickers. A file is only ever touched or removed, never rewritten, so
  two pickers cannot lose each other's update.
- The directory is swept. A file is removed when its `id` has been absent from 5 consecutive
  successful polls, whether or not a picker ever saw that session in the list.

### Other projects

Every other project that has listed sessions: a project row, then its sessions indented, most
recent first. The session rows are styled as in this project. They get no jump numbers. Project
names are disambiguated as in claude-spaces, and a custom project name wins.

Selecting a project or one of its sessions hops to that project's server. The picker writes
`switch_target` with the project path and, for a session, its `id`, then detaches. The launcher
changes directory, initializes the target's state, and only then writes `pending_load`. Writing
it earlier would lose it: state initialization wipes the directory of a server that is not
running.

There is no inactive section. To work in a folder that has no sessions, run
`claude-spaces-agents` there.

## Actions

Everything not listed is unchanged from claude-spaces (navigation, search, pane movement,
terminal keys, rename project, detach, reload, config).

| Action | Key (proposed) | What it does |
|---|---|---|
| Show | `Enter`, `Space` | switch to the session; `Enter` also focuses it |
| New session | `:c`, prefix `c` | `claude --bg` in `$PWD`, wait for its `id` to be listed, switch to it |
| Agent view | `:v`, prefix `v` | run `claude agents` in the client pane; `/resume` brings back older conversations |
| Stop | `:x`, prefix `x` | confirm, `claude stop <id>`; its terminal is kept |
| Remove | `:D`, prefix `D` | confirm, saying that work in progress is stopped; `claude rm <id>`; on success its terminal is killed |
| Shutdown | `:s`, prefix `s` | confirm, saying that terminals die when there are any; kill the tmux server; sessions keep running |

- **Prefix `a` is not taken.** As in claude-spaces it types a literal grave, for users whose
  tmux prefix is the grave.
- **Stop and remove from another pane mean the session being looked at.** Pressed with the
  prefix while the picker is not focused, they act on `shown`, not on the row the cursor was
  left on. With nothing shown, or from the picker itself, they act on the cursor row. The list
  is drawn again before the question, so the row asked about is the one highlighted.
- **Command output is shown.** A command's message goes to the picker's footer, on success as
  well as on failure. Known failures: `Workspace not trusted` from `claude --bg` in a directory
  never opened before, and `kept <id>` with a reason from `claude rm`.
- **Where it is shown.** A note is a failing poll, or else the last command's message. It has
  rows of its own between the key hints and the version: centered, in the bell colour, with an
  empty row above and below. The version stays, below it. A command's message goes away at the
  next key; a poll error stays until a poll succeeds.
  - A note longer than the pane's width is split into two rows. The break is the last space
    that keeps the first row within the width, or the width itself when there is no such
    space. The second row is cut to the width. There is no third row.
  - A list that fills the pane gives up two rows while a note is shown, and three when the
    note has two rows, so the note always has its rows and the empty ones.
  - With no sessions there is no footer, and an empty list has no text of its own. A failing
    poll is shown on the row under the header, indented and in the dim colour, and split into
    two rows by the same rule. The command's message is drawn as a note under that: its first
    row is the fourth of the pane, or the fifth under a failing poll on two rows.
  - The search view shows no note.
- **Jump numbers** go to the first ten rows of this project, in display order. claude-spaces
  gave the first slots to running sessions, a distinction that no longer exists.
- **`Workspace not trusted`.** The picker also opens agent view in the client pane, which shows
  Claude's trust dialog. The action is then repeated by hand.
- **Waiting for a new `id`.** After a new session the picker refreshes until the new `id` is
  listed, for at most 5 seconds. Then it switches to it or reports the failure. The `id` is
  taken from the first line of the command's output, `backgrounded · <id>`. If that line is
  missing, it is the entry for `$PWD` that was not in the list before the command.
- **Untouched new sessions.** The picker keeps the `id` of the last session it created in
  `new_session`. If the user switches to another session while that one is still waiting for its
  first prompt, the picker removes it with `claude rm`. Because `claude rm` stops work without
  asking, the check is made immediately before the `rm`, on a fresh poll that bypasses the
  cache: the session must be `blocked` with `status: idle`, and it must have no transcript. If
  either fails, it is left alone.
- **`claude rm` is never forced.** The picker does not pass `--discard-unpushed` or
  `--force-remove-worktree`. Those are run by hand.
- **Removed**: rename session (use `/rename` in the session; the name comes from Claude), fork
  (fork from inside the session; the fork shows up in the list like any other), hide, hide
  older, show hidden.

## Terminals

One terminal per session, keyed by `id` instead of pane ID. The claude-spaces terminal code
carries over, with the client pane as the split target:

- Each session remembers whether its terminal is visible and its orientation, `bottom` or `side`.
- The preferred size is `terminal_width`/`terminal_height`, or for a percentage the saved share.
  It fits when Claude keeps at least `min_claude_width`/`min_claude_height`.
- On every resize of the outer terminal the shown terminal is re-fitted. A percentage size that
  does not fit is squeezed. A fixed size that does not fit is hidden, unless it was opened
  without room (`.keep`), in which case it is squeezed too.
- The floor is 10 columns or 3 rows. A squeezed size is never saved as the preference.

Further rules:

- A terminal is created with `split-window` in the session's `cwd`, so a worktree session gets a
  shell in its worktree.
- Only the displayed session's terminal is in the main window. Terminal keys act on `displayed`
  (§ Displayed and shown).
- A terminal is killed after the picker's own `claude rm` succeeds, or when its `id` has been
  missing from 5 consecutive successful polls. Stopping a session keeps its terminal. A failed
  poll never kills anything: a terminal can hold a running process.
- Closing the shell closes the terminal. On the next scan its state is forgotten, and the
  terminal key opens a new one. Nothing brings a dead terminal back on its own.
- The welcome screen has no terminal. When it is shown, or a client exits, the terminal in the
  main window is parked, and comes back with its session.

### Parking

Parking never resizes a terminal. It sits in a hidden `csa:term` window pinned to the terminal's
own size, and it only moves between cells of that size.

Park:

```
SLOT=$(_tmux new-window -d -P -F '#{pane_id}' "$PLACEHOLDER")
_tmux resize-window -t "$SLOT" -x "$W" -y "$H"            # pin the window to the terminal's size
_tmux swap-pane -d -s "$TERM_PANE" -t "$SLOT" \; kill-pane -t "$SLOT"
```

Unpark, with `-v` or `-h` for the orientation:

```
_tmux join-pane -d -s "$TERM_PANE" -t "$CLIENT" -l <size>
```

- Coming out of a window of its own size, the terminal sees no resize.
- `break-pane` must not be used to park. It puts the pane in a full-size window, and following
  it with `resize-window`, even in the same chain, still resizes the terminal.
- A parked terminal does not follow the outer terminal. After the outer terminal is resized, it
  keeps its old size and is resized once at its next show. The pin is not what does this: tmux
  leaves a hidden window alone until it is selected, pinned or not (observed with the pin taken
  out). The pin is what makes the park itself free of a resize.
- **The size on unpark.** Whenever a terminal is about to leave the main window, the picker
  records the client area it sat in (`term/<id>.area`: the client pane's size without the
  terminal). If the area is still that one at the next show, and the orientation is the same,
  the terminal gets the size it has, to the cell. Computing it again from the saved share can
  land a cell off, and would also undo a size the user dragged. If the area changed, the size is
  stale and is computed from the setting or the saved share.
- A fixed-size terminal that a resize hides was squeezed by tmux first. Its record is dropped,
  so reopening it computes the size again, and marks it `.keep` when there is no room.
- Placeholders are tagged with the pane option `@csa_placeholder`. At startup and after a failed
  switch the picker kills any window whose only pane is a tagged placeholder, so a slot left
  behind by a failed chain does not stay forever.
- Hiding or showing the terminal of the displayed session changes the client pane's size while a
  client is attached. That is the user's action and costs the session one resize. The terminal
  itself is still not resized.

Measured the same way as the switches, for bottom and side terminals:

| Operation | `break-pane` and `join-pane` | Pinned slot |
|---|---|---|
| Park | 1 SIGWINCH | 0 |
| Unpark | 1 SIGWINCH | 0 |
| Outer terminal resized while parked | not applicable | 0 |

## Launch and state

The launcher follows the claude-spaces design. Each project gets its own tmux server, named from
`$PWD`. The launcher creates it if missing and attaches. When the picker leaves a `switch_target`
and detaches, the launcher changes to that directory and loops (§ Other projects).

State lives in `${XDG_RUNTIME_DIR}/claude-spaces-agents/<sanitized-cwd>/`, or under
`/tmp/claude-spaces-agents-${UID}/` when `XDG_RUNTIME_DIR` is unset.

- Server names use the prefix `csa`, state root and config use `claude-spaces-agents`, so both
  tools can run on the same project. The prefix must never start with `cs-`: claude-spaces finds
  its own servers by globbing sockets named `cs-*`, and would take these for its own.
- Preflight runs only when the launcher is about to create a server, not on a re-attach, and
  after the export in § Environment: `claude --version` is at least 2.1.325, the only version
  tested, and `claude agents --json` exits 0. Otherwise print Claude's own message and exit.
- Compatibility gate: a constant in the script is stamped into `compat_version` at launch,
  exactly when there is no live picker, so only by the launch that is about to build the
  topology. A picker that finds a different value writes `restart_required` and kills the server,
  and the launcher explains once it has the terminal back. Nothing is migrated. A restart costs
  no session, but it kills the terminals.
- `--reset` kills the server and wipes the state dir. Sessions are untouched; terminals die with
  the server.

| File | Contents |
|---|---|
| `picker_pane` | pane ID of the picker |
| `client_pane` | pane ID of the client pane |
| `displayed` | `id` of the session whose terminal layout the main window has |
| `new_session` | `id` of the last session created here, until it gets its first prompt |
| `term/<id>` | terminal pane ID |
| `term/<id>.shown` | presence = terminal should be visible |
| `term/<id>.orient` | `bottom` or `side` |
| `term/<id>.height`, `.width` | saved percentage share |
| `term/<id>.keep` | presence = fixed-size terminal opened without room |
| `term/<id>.area` | client pane size without the terminal, `WxH`, when the terminal was last in the main window |
| `compat_version` | gate constant this server's topology was built with |
| `restart_required` | marker: the picker found an incompatible server and killed it |
| `project_path` | real filesystem path of the project |
| `switch_target` | project path to hop to, and optionally the `id` to show there |
| `pending_load` | `id` to show; written by the launcher after a hop |
| `<state-root>/agents.json` | shared poll cache |

The state dir is wiped when the recorded `picker_pane` is dead, as today: `term/<id>` holds pane
IDs, and those must not outlive their server.

Persistent files, respecting `$XDG_CONFIG_HOME` and `$XDG_DATA_HOME`:

| File | Purpose |
|---|---|
| `~/.config/claude-spaces-agents/config` | configuration (see § Open questions) |
| `~/.local/share/claude-spaces-agents/project_names` | custom project names |
| `~/.local/share/claude-spaces-agents/seen/<id>` | empty file; its mtime is when the session was last shown |

## Polling

One `claude agents --json --all` call costs about 0.15 s of CPU. At one call per second that is
roughly 15% of a core per picker.

- `poll_interval`, default 2 seconds.
- Polling runs only while a client is attached to the server (`#{session_attached}`). A detached
  picker makes no calls, and refreshes at once when a client attaches. Attention does not suffer:
  it is derived from the state and the transcript, not from watching.
- The result is cached in `<state-root>/agents.json`, shared by every picker. A picker reuses the
  cache when it is younger than the interval, so the cost does not grow with open projects.
- Writes are a temp file plus `mv`. Two pickers refreshing at once both write a complete file and
  the last rename wins; a reader never sees a partial one.
- The picker's own actions (new, stop, remove) refresh immediately and rewrite the cache.
- A failed call keeps the last list and shows the error. An empty list is never shown in place of
  an error.

## Things that are easy to break

- **Empty targets.** `respawn-pane -k -t ""` respawns the active pane, which can be the picker.
  The same goes for `swap-pane`, `join-pane`, `kill-pane`, `resize-window` and `select-pane -T`,
  which would retitle the active pane. Guard every target.
- **Stale pane titles.** tmux keeps a title across `respawn-pane` and after its program exits.
  Any respawn of the client pane that does not set a marker lets following adopt the session
  that was just left. Respawn only through the helper.
- **Unvalidated JSON values.** `id`, `sessionId` and `cwd` end up in command strings, and `name`
  on the screen.
- **Geometry changes while attached.** Moving a terminal before the old client is gone resizes
  the session being left.
- **Parking with `break-pane`.** It resizes the terminal, and `resize-window` afterwards does
  not undo that.
- **Split chains.** The marker, the placeholder, the terminal moves and the attach must stay one
  `_tmux` call, or the placeholder is visible and a stale title can be read.
- **Keying state by `sessionId`.** Every command takes `id`, and `sessionId` is documented as
  present only when set.
- **Matching on display names.** Following compares the pane title with Claude's `name`. Any
  picker-side renaming of sessions would break it.
- **Killing terminals on list data.** A terminal can hold a running process. Never kill one on a
  failed poll or a single missing entry.
- **Reading Claude's state files.** They have what `--json` lacks, and they change between
  versions. The transcript tail is the only exception.
- **Transcript mtime as activity.** It moves when a process stops, restarts, or is attached
  after a while. Use it only to decide when to read the tail again.
- **Trusting the transcript format.** It is internal. When no matching record is found, fall back
  to the mtime for age and order. A format change must cost an exact age, never the list, and it
  must never raise a bell.
- **Removing a session on stale state.** `claude rm` stops work without asking. Check on a fresh
  poll, right before the call.
- **`--cwd` for scoping.** It is a prefix match.

## Dropped from claude-spaces

Filler panes and reaping, `panes/<num>`, `new_pane` tracking, the transcript scan and name
resolution, the session names and hidden files (project names are kept), inactive-project
discovery, `cs_discover_servers` and the `.servers/` registry, the `alert-bell` hook and the Stop
hook it needed (the focus hooks stay), and deleting Claude's `sessions/<pid>.json` on close.

## Testing

Same harness as claude-spaces: an isolated tmux server and the script's functions evaluated up
to the entrypoint marker. Claude is replaced by a fake `claude` on `PATH`:

- `agents --json --all` prints a fixture file.
- `attach <id>` records every SIGWINCH to a file and sleeps. Like the real one, it sets no title.
  Tests set the pane title themselves to simulate agent view and a session opened from it.
- `--bg`, `stop` and `rm` edit the fixture.
- Transcripts are fixture files as well, so last activity, the age column and Finished, unseen
  can be tested, including a housekeeping record appended after the last turn.

Terminals run a shell stand-in that records the directory it started in and every SIGWINCH.

`run_tests` runs everything; `run_tests <test_name>` runs one test.

**After every test** a check looks at what is left: the panes, the windows and the state files.

- the picker pane is alive and was never respawned;
- exactly one client pane, beside the picker;
- no placeholder is left anywhere;
- every tracked terminal is alive; at most one is in the main window, it belongs to `displayed`
  and is marked shown; a displayed session's terminal that is marked shown is not parked;
- the main window holds nothing else, and every other pane is a parked terminal alone in its
  window.

The check has a test of its own, which builds each kind of leftover and expects it to be named.

**SIGWINCH.** Terminals are counted across every switch, park and show. The client of the
session being shown is counted too. The client of the session being *left* is not: it dies in
the same tmux call, before it could record anything. A resize in a new client's first moments
cannot be seen either. So the rule "geometry never changes while a client is attached" is also
tested as an order: in the one tmux call of a switch the placeholder comes before any terminal
move, and the new client is started last. One test resizes on purpose and expects both counters
to move.

**The launcher** is tested with the real script, started in a pane of a second tmux server with
a scratch `HOME`: launch, detach, re-attach, the prefix table, the preflight, the compatibility
gate, a hop to another project, and parking a terminal with a real client attached.

**Every test has been seen failing.** `run_breaks` holds one or more breaks per test:
lines of `claude-spaces-agents` to damage and the tests that must go red. It applies each to a copy,
runs those tests, and reports any that stay green, any break whose lines are no longer in the
script, and any test no break names. A few breaks damage the test file instead, for the check
that runs after every test.

## Verified

Checked on Claude Code 2.1.325, with throwaway background sessions in an isolated tmux server.

| Check | Result |
|---|---|
| `claude --bg` with no prompt | Works. Exit 0 in 0.4 s. The first line of stdout is `backgrounded · <id>`. The session is `blocked` with `status: idle`. Trust is inherited from a trusted parent directory. |
| `respawn-pane -k` on an attached client, mid-turn | The session keeps working, in the same process. |
| Size on attach | Attaching gives the session the client's size. The session keeps it while detached, and re-attaching at the same size changes nothing. A new session starts at 200x50. |
| Switch latency | 180 to 220 ms from the respawn to the first paint. |
| Pane titles | As listed in § Following the client. |
| Exit status of `claude attach` | 0 after `Ctrl+Z`, after leaving agent view, and when its session is stopped. 1 when the session does not exist. Double `Ctrl+C` in a session goes to agent view; it does not exit. |
| Fork | `claude --bg --resume <sessionId> --fork-session` creates a new row, `blocked` with `status: idle`, carrying the source's name. |
| Waiting on the user | A session that asked a question is `blocked`, `status: waiting`, `waitingFor: input needed`. |
| `claude stop` on an idle session | The row stays `done`, with no `pid` and no `status`. Attaching starts a new process. |
| `claude rm` on a working session | Removes it at once (`removed <id>`, exit 0), with no confirmation. The transcript is kept. |
| Transcript | The mtime fails as an activity time: it moved on stop and on restart with no conversation activity. The records carry their own timestamps, and the last `user`, `assistant` or `turn_duration` record gives the real time. Reading it from the final 256 KB of a 4.8 MB transcript took 5 ms. A session with no prompt yet has no transcript. |
| `startedAt` | The process start. It changed when a stopped session was woken. |
| Two clients on one session | Both stay attached and mirror the session. It has one size, which followed the second client. |

Not verified:

- **A session that moved into a worktree: its `cwd`, and where its transcript lives.** Testing it
  means letting a session edit files in a real repository, which by default also pushes a branch
  and opens a draft pull request.
- **`/resume` in agent view.** Its picker lists the real repository's past sessions.
- **`claude agents --json` with no supervisor running.** Stopping the supervisor would end live
  sessions.
- **The idle reaper.** It acts after about an hour. Its effect on the transcript is inferred from
  `claude stop`.
- **Older versions.** Only 2.1.325 was tested, so that is the preflight minimum.

## Open questions

- **Retention.** How long finished rows stay in `--all` is undocumented.
- **Config.** Own file with the claude-spaces keys, or read the claude-spaces config.
- **Keys.** The assignments in § Actions are proposals.
