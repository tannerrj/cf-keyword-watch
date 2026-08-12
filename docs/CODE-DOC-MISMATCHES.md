# Code and documentation mismatches in the client scripting code

Found while reading `common/script.c`, `common/p_cmd.c`, and
`common/client.c` to build this script. Recorded here because they are
upstream issues, not issues with cf-keyword-watch.

Nothing here has been patched or reported yet. Line numbers are from the tree
that was read and may drift.

## 1. Stale claim that scripting does not work on Windows

`script.c` line 96:

    /*
     * This does not work under Windows for now.  Someday this will be fixed :)
     */

The code immediately below contradicts this. There is a complete `WIN32`
implementation: `emulate_read` and `emulate_write` wrapping `ReadFile` and
`WriteFile`, a full `CreatePipe` / `DuplicateHandle` / `CreateProcess` branch
in `script_init()`, `HANDLE` members in `struct script`, `PeekNamedPipe`
polling in `script_process()`, and `GenerateConsoleCtrlEvent` for kill.

Fix: delete the comment.

## 2. Watch does not automatically pick up future server commands

`script.c` lines 31 to 33 claim the watch is checked before the client
processes the command, so it will automatically handle new options added in
the future.

`client.c` lines 258 to 264 show otherwise:

    for(i = 0; i < NCOMMANDS; i++) {
        if (strcmp(cmdin, commands[i].cmdname) == 0) {
            script_watch(cmdin, data, len, commands[i].cmdformat);
            commands[i].cmdproc(data, len);
            break;
        }
    }

`script_watch()` is reached only on a match against the `commands[]` table. A
command not in the table falls through to `i == NCOMMANDS`, which logs an
error, shows a "server sent an unrecognized command" dialog, and calls
`client_disconnect()`.

So a new server command does not reach scripts. It disconnects the client.

Fix: correct the comment to say scripts see exactly the commands in the
`commands[]` table.

## 3. Both in-file command lists are incomplete

The file header list in `script.c` (roughly lines 28 to 61) omits `localcmd`.
The inline list above the dispatch chain in `script_process_cmd()` (roughly
lines 1118 to 1128) omits `sync`.

The handlers actually implemented are: `sync`, `watch`, `unwatch`, `request`,
`issue`, `localcmd`, `draw`, `monitor`, `unmonitor`.

`scriptkillall` is registered in `p_cmd.c` but is absent from the header docs
in `script.c`.

## 4. help_script understates the syntax

`p_cmd.c`, `help_script()`:

    "Syntax: script <path>\n\n"

`script_init()` splits its parameter on spaces and builds an `argv[]` of up to
256 entries before `execvp`. Arguments are supported and should be documented
as `script <path> [args]`.

## 5. Bare WIN32 guards

`script.c` uses unprefixed `WIN32` at every guard site, roughly fourteen of
them. Other files in this tree have been converted to `_WIN32`.

mingw-w64 predefines the unprefixed `WIN32` only in GNU dialect mode. Under
`-std=c99` or `-ansi` it is suppressed while `_WIN32` survives, at which point
`script.c` takes the POSIX branch and tries to include `sys/socket.h` and
`sys/wait.h`.

This fails loudly at compile time rather than silently disabling scripting, so
it is a consistency issue rather than a latent runtime bug.

## 6. Multi-character constant in a strchr call

`script.c`, in `script_process()`, Windows branch:

    while (scripts[i].cmd_count == sizeof(scripts[i].cmd)-1
    #ifndef WIN32
            || strchr(scripts[i].cmd, '\n'))
    #else
            || strchr(scripts[i].cmd, '\r\n'))
    #endif /* WIN32 */

`'\r\n'` is a multi-character constant, not a string. GCC evaluates it to
`0x0D0A`, which `strchr` truncates to `char` as `0x0A`, so it accidentally
searches for a newline and works. It is implementation-defined and triggers
`-Wmultichar`.

`script_process_cmd()` already strips a trailing `\r` a few lines later, so
the correct fix is to use `'\n'` in both branches and remove the `#ifdef`
entirely.

## 7. Inconsistent error message on missing argument

The POSIX branch of `script_init()` points the user at the help system:

    "Please specify a script to start. For help, type 'help script'."

The Windows branch does not, and misspells "specify":

    "Please specifiy a script to launch!"
