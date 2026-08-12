#!/bin/sh
#
# cf-keyword-watch.sh - Crossfire client script: watch message-window output
#                       for keywords and alert the player.
#
# Copyright (C) 2026  Rick Tanner
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <https://www.gnu.org/licenses/>.
#
# Verified against common/script.c and common/p_cmd.c (GTK3 client tree).
#
# Launch from the client console:
#     script /path/to/cf-keyword-watch.sh fire dragon
#
# On Windows the client calls CreateProcess() with the whole command line, so
# point it at bash and pass this file as the first argument:
#     script C:/msys64/usr/bin/bash.exe /c/scripts/cf-keyword-watch.sh fire
# NOTE: no quote handling exists in script_init(), so avoid paths with spaces.
#
# Live control from the client console:
#     scripttell cf-keyword-watch.sh add lightning
#     scripttell cf-keyword-watch.sh del fire
#     scripttell cf-keyword-watch.sh list
#     scripttell cf-keyword-watch.sh debug 1
#
# Stop it:
#     scriptkill cf-keyword-watch.sh     (or just "scriptkill" if it is alone)
#
# Environment:
#     CF_WATCH_LOG    log file path (default ~/.crossfire/keyword-watch.log)
#     CF_WATCH_DEBUG  1 = log every line received (default 0)
#     CF_PLAYER_NAME  set by the client on POSIX only, not on Windows
#     CF_SERVER_NAME  set by the client on POSIX only, not on Windows

LOG="${CF_WATCH_LOG:-$HOME/.crossfire/keyword-watch.log}"
DEBUG="${CF_WATCH_DEBUG:-0}"
KEYWORDS="$*"

mkdir -p "$(dirname "$LOG")" 2>/dev/null

# --- client output -------------------------------------------------------
# script_process_cmd() skips to the first digit, atoi()s it as the color, then
# passes the remainder to draw_ext_info(). Color 3 is NDI_RED in newclient.h.
say() {
    echo "draw 3 $1"
}

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG"
}

# --- desktop notification ------------------------------------------------
# MUST be non-blocking. script_init() sets O_NDELAY on the client's write end
# and script_watch() ignores the write() return value, so if this script stops
# reading stdin the client silently drops watch lines. Every branch backgrounds.
notify() {
    body="$1"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "Crossfire" "$body" &
    elif command -v terminal-notifier >/dev/null 2>&1; then
        terminal-notifier -title "Crossfire" -message "$body" &
    elif command -v powershell.exe >/dev/null 2>&1; then
        # Dependency-free Windows fallback: tray balloon, not a real toast.
        # Swap in BurntToast or SnoreToast if you want a proper notification.
        powershell.exe -NoProfile -WindowStyle Hidden -Command "
            Add-Type -AssemblyName System.Windows.Forms
            \$n = New-Object System.Windows.Forms.NotifyIcon
            \$n.Icon = [System.Drawing.SystemIcons]::Information
            \$n.Visible = \$true
            \$n.ShowBalloonTip(5000, 'Crossfire', '$body', 'Info')
            Start-Sleep -Seconds 6
            \$n.Dispose()
        " >/dev/null 2>&1 &
    else
        printf '\a' >&2 &
    fi
}

# --- field stripping -----------------------------------------------------
# CONFIRMED: common/client.c registers both drawinfo and drawextinfo as ASCII,
# so script_watch() emits: watch <cmd> <payload>  with payload passed through
# verbatim via %s (DoClient() NUL-terminates the buffer first).
# The drawextinfo payload from the server is: <color> <type> <subtype> <text>
# so three leading integers get stripped. drawinfo is: <color> <text>, one.
strip_fields() {
    _n=$1
    _s=$2
    while [ "$_n" -gt 0 ]; do
        _rest=${_s#* }
        [ "$_rest" = "$_s" ] && break
        _s=$_rest
        _n=$((_n - 1))
    done
    printf '%s' "$_s"
}

# --- keyword matching ----------------------------------------------------
check_keywords() {
    text="$1"
    [ -z "$text" ] && return
    lower=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')

    for kw in $KEYWORDS; do
        kwlower=$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
            *"$kwlower"*)
                say "[match: $kw] $text"
                notify "$kw -- $text"
                log "MATCH ($kw): $text"
                ;;
        esac
    done
}

# --- startup -------------------------------------------------------------
log "started; player=${CF_PLAYER_NAME:-unknown} server=${CF_SERVER_NAME:-unknown} keywords: $KEYWORDS"

# Subscribe. An empty watch string matches every command in script_watch(),
# so "watch" alone is the discovery-pass subscription; the two below are the
# message-window channels.
echo "watch drawextinfo"
echo "watch drawinfo"

if [ -z "$KEYWORDS" ]; then
    say "keyword-watch running with no keywords; logging only"
else
    say "keyword-watch running; watching for: $KEYWORDS"
fi

# --- main loop -----------------------------------------------------------
while IFS= read -r line; do
    line=${line%"$(printf '\r')"}
    [ "$DEBUG" = "1" ] && log "RAW: $line"

    case "$line" in
        "watch drawextinfo "*)
            payload=${line#watch drawextinfo }
            # Shop inventory and other bulk output can arrive as a multi-line
            # block in one payload; split so each item is checked separately.
            printf '%s\n' "$(strip_fields 3 "$payload")" | while IFS= read -r l; do
                check_keywords "$l"
            done
            ;;

        "watch drawinfo "*)
            payload=${line#watch drawinfo }
            check_keywords "$(strip_fields 1 "$payload")"
            ;;

        "scripttell "*)
            arg=${line#scripttell }
            verb=${arg%% *}
            rest=${arg#* }
            [ "$rest" = "$verb" ] && rest=""
            case "$verb" in
                add)
                    KEYWORDS="$KEYWORDS $rest"
                    say "watching: $KEYWORDS"
                    log "keywords now: $KEYWORDS"
                    ;;
                del)
                    new=""
                    for kw in $KEYWORDS; do
                        [ "$kw" = "$rest" ] || new="$new $kw"
                    done
                    KEYWORDS="$new"
                    say "watching: $KEYWORDS"
                    log "keywords now: $KEYWORDS"
                    ;;
                list)
                    say "watching: $KEYWORDS"
                    ;;
                debug)
                    DEBUG="$rest"
                    say "debug set to $DEBUG"
                    ;;
                *)
                    say "unknown command: $verb (add|del|list|debug)"
                    ;;
            esac
            ;;
    esac
done

log "stdin closed; exiting"
