# cf-keyword-watch

A client-side script for the Crossfire GTK client that watches the message
window for keywords and alerts the player when one appears.

The motivating case: you walk into a shop, check the inventory sign, and want to know
whether anything in the inventory has "fire" in its name without reading the
whole wall of text. The script watches every message the client receives,
matches it against a keyword list, and alerts you both in the client's own
message pane and through an OS desktop notification.

## How it works

The Crossfire client has a scripting interface built into `common/script.c`.
It is not a plugin system: a script is a separate process, launched by the
client, with two pipes between them. The script subscribes to the server
commands it cares about, and the client forwards copies of those commands as
plain text lines on the script's stdin. The script writes commands back on
stdout.

This script subscribes to `drawinfo` and `drawextinfo`, which together carry
everything that lands in the message window.

Because the transport is line-oriented text on stdin and stdout, the script is
written in POSIX shell. That avoids the stdout buffering trap that catches
people writing these in Python, and sidesteps MSYS2 path translation on
Windows builds.

See `docs/CLIENT-SCRIPTING-NOTES.md` for the protocol details, all of them
verified against client source rather than against the wiki.

## Requirements

- A Crossfire GTK client with scripting compiled in (GTK2 or GTK3)
- A POSIX shell
- Optional, for desktop notifications:
  - Linux: `notify-send` (libnotify)
  - macOS: `terminal-notifier`
  - Windows: PowerShell (a tray balloon fallback is built in and needs no
    extra install)

## Installation

Put `cf-keyword-watch.sh` anywhere the client can execute it, and make it
executable:

    chmod +x cf-keyword-watch.sh

Avoid paths containing spaces. The client's `script_init()` splits its
argument on spaces with no quote handling, so a path like
`C:/Program Files/scripts/cf-keyword-watch.sh` will not launch.

## Usage

From the client console (press the apostrophe key first, or type into the
command entry box):

    script /path/to/cf-keyword-watch.sh fire dragon

On Windows the client calls `CreateProcess()` with the whole command line, and
it will not run a `.sh` directly. Point it at bash and pass the script as the
first argument:

    script C:/msys64/usr/bin/bash.exe /c/scripts/cf-keyword-watch.sh fire

### Live control

The client's `scripttell` command sends a line to a running script. Run
`scripts` first to get the index, then address the script by that:

    scripttell 1 add lightning
    scripttell 1 del fire
    scripttell 1 list
    scripttell 1 debug 1

The index is the reliable form. A script is registered under the string you
passed to `script`, and a name argument is matched as a *prefix* of it, so if
you launched with an absolute path then the bare file name will not resolve:

    script /home/you/scripts/cf-keyword-watch.sh fire
    scripttell cf-keyword-watch.sh debug 1     -> No such running script
    scripttell /home/you/scripts/cf debug 1    -> works, prefix of the name

The name cannot be omitted. `scripttell debug 1` reads `debug` as the script
name and fails the same way.

### Listing and stopping

    scripts
    scriptkill 1
    scriptkillall

`scripts` lists the running scripts with the indices and registered names that
`scripttell` and `scriptkill` expect. `scriptkill` with no argument works when
exactly one script is running; otherwise pass an index or a name prefix.

## Configuration

Set these in the environment before launching the client.

| Variable | Default | Meaning |
| --- | --- | --- |
| `CF_WATCH_LOG` | `~/.crossfire/keyword-watch.log` | Log file path |
| `CF_WATCH_DEBUG` | `0` | Set to `1` to log every line received |

The client sets `CF_PLAYER_NAME` and `CF_SERVER_NAME` in the script's
environment, but only on POSIX. The Windows `CreateProcess()` branch does not
set them, so treat both as optional.

## Known limitations

- Keyword matching is case-insensitive substring matching on whitespace
  separated words. Multi-word phrases passed in quotes get split at launch.
  Phrase matching needs the keyword list changed to newline delimited.
- The three-field strip on `drawextinfo` payloads assumes the server sends
  `<color> <type> <subtype> <text>`. Confirm with `debug 1` against your own
  server before relying on it.
- Notification calls are all backgrounded on purpose. The client sets
  `O_NDELAY` on its write end of the pipe and ignores the `write()` return
  value, so a script that blocks will cause the client to silently drop
  messages. Do not remove the trailing `&` from any branch of `notify()`.
- The client's `script_process()` handles one script per call and returns
  immediately. With several scripts running, a chatty one can starve the
  others.

## License

Copyright (c) 2026 Rick Tanner

Distributed under the GNU General Public License, either version 2 of the
License or, at your option, any later version, matching the license of the
Crossfire client it is written against. `LICENSE` holds the full text of
version 2.
