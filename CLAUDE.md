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

- The three-field strip on `drawextinfo` payloads assumes the server sends
  `<color> <type> <subtype> <text>`. This has not been confirmed against a
  live server. Confirm by running with `CF_WATCH_DEBUG=1` and reading the log,
  or by reading `DrawExtInfoCmd` in the client tree.
- `LICENSE` now holds the verbatim GPL-2.0 text from
  `https://www.gnu.org/licenses/old-licenses/gpl-2.0.txt`. Do not edit it; the
  license text is only valid unmodified.
- The copyright holder line and year live in the `## License` section of
  `README.md`, not in `LICENSE`. They may need changing depending on which
  handle this is published under.
- `cf-keyword-watch.sh` carries the GPL notice header from the appendix at the
  end of `LICENSE`, with the "or (at your option) any later version" clause
  dropped so it reads as GPL-2.0-only, matching the `README.md` statement. If
  the project should be GPL-2.0-or-later instead, that clause has to be
  restored in the script header and the README wording changed to match.
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
