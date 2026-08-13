# CLAUDE.md

Context for Claude Code sessions in this repository.

## What this is

`cf-keyword-watch.sh` is a client-side script for the Crossfire GTK client. It
subscribes to the client's message-window output, matches incoming text
against a keyword list, and alerts the player in the client message pane and
through an OS desktop notification.

It is a standalone POSIX shell script. There is no build step and no
dependency to install. The deliverable is the one script plus its docs.

## Read these first

- `docs/CLIENT-SCRIPTING-NOTES.md` - the client scripting protocol, derived by
  reading client source directly. This is the authority for how the script
  talks to the client. It is more accurate than the Crossfire wiki.
- `docs/CODE-DOC-MISMATCHES.md` - seven places where the client's own comments
  and help text contradict its code. Unpatched and unreported as of this
  writing.

## Working conventions

- Trust code over documentation and comments. Where in-tree comments disagree
  with the code they describe, the code wins. Flag the mismatch rather than
  silently following either one.
- No ANSI escapes or non-ASCII characters in `.md` or `.txt` files. No smart
  quotes, em dashes, arrows, or box-drawing characters. The repository is
  currently clean; verify with:

      grep -rPn '[^\x00-\x7F]' --include='*.md' --include='*.txt' .

- POSIX shell only in `cf-keyword-watch.sh`. No bashisms. It must run under
  MSYS2 bash on Windows and under dash or sh elsewhere. Verify with
  `sh -n cf-keyword-watch.sh` and `shellcheck --shell=sh cf-keyword-watch.sh`.

## Invariants that look like bugs but are not

- Every branch of `notify()` ends in `&`. This is required, not stylistic. The
  client sets `O_NDELAY` on its write end of the pipe and ignores the return
  value of `write()`, so a script that blocks causes the client to silently
  drop forwarded messages. Do not remove the backgrounding.
- The PowerShell branch of `notify()` wraps its work in a `( ... ) &` subshell
  and doubles every single quote in the body first. Both parts are required.
  The body is interpolated into a PowerShell single-quoted string, and message
  text is server-supplied, so an item or player name containing an apostrophe
  would close the string early and leave the rest to be parsed as code.
  Doubling is how PowerShell escapes a quote inside such a string. The
  subshell keeps the `sed` off the read loop while preserving the rule above.
- The `*)` catch-all at the end of the main loop is how multi-line payloads
  are handled, and is load-bearing. Message text may contain embedded
  newlines, so bulk output such as shop inventory arrives as several reads.
  Only the first carries the `watch <cmd>` prefix and the leading integer
  fields; the rest fall through to the catch-all and are checked as plain
  text. Do not field-strip them, and do not add a branch above the catch-all
  that swallows unrecognised lines.
- The `watch*|monitor*` branch just above the catch-all exists so that
  protocol lines for commands this script did not subscribe to, and bare
  `watch <cmd>` lines carrying no data, are not mistaken for message text.
- `line=${line%"$(printf '\r')"}` trims a possible trailing carriage return.
  Keep it; the client's Windows path has its own line-ending quirks. The inner
  quotes are required by SC2295 and must stay.

## Open items

- The three-field strip on `drawextinfo` is confirmed against a live server.
  A shop listing arrives as `watch drawextinfo 0 9 1` with the text starting
  on the next line, so the layout is `<color> <type> <subtype>` exactly as
  assumed. See the confirmed block in `docs/CLIENT-SCRIPTING-NOTES.md`.
  Because the head line carries no text for this shape, `strip_fields` returns
  empty when it runs out of fields rather than the trailing integer; without
  that, a numeric keyword false-matches on every `drawextinfo`.
- `LICENSE` now holds the verbatim GPL-2.0 text from
  `https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt`. Do not edit it; the
  license text is only valid unmodified.
- The copyright holder line and year live in the `## License` section of
  `README.md`, not in `LICENSE`. They may need changing depending on which
  handle this is published under.
- The project is GPL-2.0-or-later, matching the Crossfire client it is written
  against. `cf-keyword-watch.sh` carries the notice header from the appendix
  at the end of `LICENSE`, verbatim, including the "either version 2 of the
  License, or (at your option) any later version" clause; `README.md` says the
  same in prose. `LICENSE` holds the version 2 text, which is correct for
  or-later: the extra permission is granted by the notice, not by the license
  file. The header also carries `SPDX-License-Identifier: GPL-2.0-or-later`,
  which is what license scanners and GitHub read; without it they infer plain
  GPL-2.0 from `LICENSE` alone. Keep all four consistent if any one changes.
- shellcheck 0.11.0 reports zero findings under `-s sh`, `-s dash`, and
  `-s bash`, and `sh -n` passes. The one first-run finding was SC2295 on the
  carriage-return trim, fixed by quoting rather than by a disable comment. The
  subshell in the `drawextinfo` branch drew no warning, contrary to what this
  file previously predicted. There are no `# shellcheck disable` comments in
  the tree; keep it that way if a real fix is available instead.

## Out of scope for this repository

The client source files that were read to produce these notes
(`common/script.c`, `common/p_cmd.c`, `common/client.c`) are not vendored
here. Patches against the client belong in the client tree, not this one.
`docs/CODE-DOC-MISMATCHES.md` is the record of what such patches would fix.
