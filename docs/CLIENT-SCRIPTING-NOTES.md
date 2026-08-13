# Crossfire client scripting: protocol notes

Everything below was read out of client source, not documentation. Where the
in-tree comments disagree with the code, the code is treated as authoritative
and the disagreement is recorded in `CODE-DOC-MISMATCHES.md`.

Files referenced:

- `common/script.c`
- `common/p_cmd.c`
- `common/client.c`

## Model

A script is an external process, not a loaded module. The client opens two
pipes, forks (POSIX) or calls `CreateProcess()` (Windows), and wires the
script's stdin and stdout to those pipes.

A newly started script receives nothing. It must subscribe first.

## Console commands

Registered in the `CommonCommands[]` table in `p_cmd.c`:

| Command | Effect |
| --- | --- |
| `script <path> [args]` | Launch a script |
| `scripts` | List running scripts |
| `scriptkill <name or index>` | Stop one script |
| `scriptkillall` | Stop all scripts |
| `scripttell <name> <text>` | Send a line to a running script |

The help text for `script` documents only `script <path>`, but `script_init()`
splits its parameter on spaces and builds an `argv[]` of up to 256 entries
before `execvp`, so arguments are supported.

`script_by_name()` resolves the name argument by numeric index first, then by
string prefix. A NULL name resolves to script 0 when exactly one script is
running.

Observed against a running GTK2 client rather than read from source: the name
a script is registered under is the string passed to `script`, so an
absolute-path launch registers the absolute path. Because the match is a
prefix and not a substring, the bare file name then fails to resolve and the
client answers "No such running script". The index from `scripts` avoids the
question entirely. This has not been traced back to the assignment in
`script_init()`; if the code is read later, confirm and drop this caveat.

Under `#ifdef HAVE_LUA` the same table also registers `lua_load`, `lua_list`,
and `lua_kill`, and `extended_command()` calls `script_lua_command()` ahead of
`handle_local_command()`. That is an in-process Lua engine, entirely separate
from the external-process interface described here.

## Commands the script writes to stdout

Handled by `script_process_cmd()` in `script.c`:

| Command | Effect |
| --- | --- |
| `watch <command>` | Forward copies of that server command to the script |
| `unwatch <command>` | Cancel a watch |
| `request <data type>` | Ask the client for current state |
| `issue <repeat> <must_send> <command>` | Send a command to the server |
| `localcmd <command> [<params>]` | Run a client-side console command |
| `draw <color> <text>` | Print into the client message window |
| `monitor` | Receive copies of every command sent to the server |
| `unmonitor` | Stop monitoring |
| `sync <n>` | Wait until all but n commands are acknowledged |

An unrecognised command causes the client to print a "malfunction" complaint
into the message window, naming the script and echoing the bad line.

### watch

An empty watch string matches every command, so a bare `watch` with no
argument subscribes to everything. Useful for a discovery pass.

That breadth is bounded by the `commands[]` table in `client.c`. Only commands
in that table ever reach `script_watch()`.

### draw

The parser skips forward to the first digit, `atoi()`s it as the colour, then
passes the remainder of the line to `draw_ext_info()` with type
`MSG_TYPE_CLIENT` and subtype `MSG_TYPE_CLIENT_SCRIPT`. Colour constants live
in `newclient.h`; `NDI_RED` is 3.

## Lines the client writes to the script's stdin

### watch output

Format depends on the `CmdFormat` in the `commands[]` table entry:

| Format | Line shape |
| --- | --- |
| `ASCII` | `watch <cmd> <payload>` |
| `SHORT_INT` | `watch <cmd> <short> <int>` |
| `SHORT_ARRAY` | `watch <cmd> <n> <n> ...` |
| `INT_ARRAY` | `watch <cmd> <n> <n> ...` |
| `STATS` | One line per stat, e.g. `watch stats hp 42` |
| `MIXED`, `NODATA`, default | `watch <cmd> <n> bytes unparsed: <hex bytes>` |

A command carrying no data produces a bare `watch <cmd>`.

The `MIXED` fall-through to a hex dump is explicitly documented in the source
as something scripts should not depend on.

### Message window commands

Both relevant entries in `client.c` are `ASCII`:

    { "drawinfo",        (CmdProc)DrawInfoCmd, ASCII },
    { "drawextinfo",     (CmdProc)DrawExtInfoCmd, ASCII},

So the script receives:

    watch drawinfo <color> <text>
    watch drawextinfo <color> <type> <subtype> <text>

`DoClient()` NUL-terminates the receive buffer before splitting on the first
space, so the payload is passed through with `%s` verbatim. Message text may
contain embedded newlines; bulk output such as shop inventory can arrive as
one payload spanning several display lines.

### monitor output

    monitor <repeat> <must_send> <command>

or, from `script_monitor_str()`, just `monitor <command>`.

### scripttell output

    scripttell <text>

The script name given on the console is stripped by `script_tell()` before the
write, so the script never sees it.

### Item data

`script_send_item()` emits:

    <header> tag num weight flags type name

`weight` is in grams (the float weight multiplied by 1000 and rounded).
`flags` is a bitmask, high bit first:

    read  unidentified  magic  cursed  damned  unpaid  locked  applied  open  was_open  inv_updated
    1024  512           256    128     64      32      16      8        4     2         1

A source comment notes that a `blessed` flag has not been added yet.

## Line endings

The client always writes `\n`. `script_process_cmd()` trims a trailing `\r` if
present, so a script may send either `\n` or `\r\n`.

## Backpressure

`script_init()` sets `O_NDELAY` on the client's write end of the pipe, and
`script_watch()` ignores the return value of `write()`. A script that stops
reading its stdin will cause the client to drop forwarded messages with no
error reported anywhere. Any work a script does in response to a message
should be backgrounded or otherwise kept short.

## Scheduling

`script_process()` services one script per invocation and returns immediately
afterward. With multiple scripts running, a high-traffic script can starve the
others.

## Environment passed to the script

On POSIX, `script_init()` sets in the forked child:

- `CF_PLAYER_NAME`
- `CF_SERVER_NAME`

The Windows `CreateProcess()` branch does not set either.

## Platform notes

Scripting is implemented on both POSIX and Windows.

The Windows implementation uses `CreatePipe()` plus `DuplicateHandle()` for
the pipes, `CreateProcess()` to launch, `PeekNamedPipe()` polling in place of
`select()`, `ReadFile`/`WriteFile` behind `emulate_read`/`emulate_write`
macros, and `GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, ...)` in place of
`kill(SIGHUP)`.

`CreateProcess()` is called with `lpApplicationName` NULL and the entire
command line as `lpCommandLine`, and the client does no quoting. Paths
containing spaces will not launch.
