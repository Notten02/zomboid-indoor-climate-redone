#!/usr/bin/env bash
# A local, non-Steam dedicated server from the game install with this mod, for manual multiplayer play-tests with
# tools/mp-client.sh. It never touches ~/Zomboid: the server has its own cache dir. (Scripted tests use the E2E bench
# instead, see tests/e2e/README.md.)
#
#   tools/mp-server.sh start [--fresh]   copy the mod, write the config, start in the background, wait until it listens
#   tools/mp-server.sh cmd TEXT          type a command on the server console (save, servermsg "hi", ...)
#   tools/mp-server.sh stop              save, quit and wait for the server to exit
#   tools/mp-server.sh status
#
# Settings (environment variables, all optional):
#   ICR_MPTEST_DIR      root of the test cache dirs        default: <repo>/.cache/mptest (git-ignored)
#   ICR_SERVER_NAME     server name (config file names)    default: icrtest
#   ICR_ADMIN_PASSWORD  password of the "admin" account    default: admin
#   ICR_SERVER_DEBUG    1 passes -debug to the server       default: 1
#   PZ_GAME_DIR         the game's projectzomboid folder    default: the Steam library install under /mnt/games
#
# What start does:
#   1. copies the mod into <cache>/mods/IndoorClimateRedone. A non-Steam dedicated server finds local mods there, not
#      in Workshop/ (42.21: "required mod ... not found"). A copy, never a symlink;
#   2. <cache>/Server/<name>.ini: written with our keys on the first start, patched on later starts (Mods,
#      WorkshopItems, Open, Public, MaxPlayers, PauseEmpty). 42.21 keeps a partial ini and adds the missing keys;
#   3. <cache>/Server/<name>_SandboxVars.lua: IndoorClimateLite.DebugLogging = true once the server has written the
#      file and the mod has that option (the first start writes the file: stop and start again to switch it on);
#   4. starts the server with its stdin on a fifo, so `cmd` and `stop` can type on its console.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${ICR_MPTEST_DIR:-$REPO/.cache/mptest}"
NAME="${ICR_SERVER_NAME:-icrtest}"
ADMIN_PASSWORD="${ICR_ADMIN_PASSWORD:-admin}"
GAME="${PZ_GAME_DIR:-/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid}"
MOD_ID=IndoorClimateRedone
CACHE="$ROOT/server"
INI="$CACHE/Server/$NAME.ini"
SANDBOX="$CACHE/Server/${NAME}_SandboxVars.lua"
LOG="$ROOT/server.log"
FIFO="$ROOT/server.fifo"
PGID_FILE="$ROOT/server.pgid"

die() { echo "mp-server: $*" >&2; exit 1; }

running() { [ -f "$PGID_FILE" ] && kill -0 -- "-$(cat "$PGID_FILE")" 2>/dev/null; }

# key=value in the ini: replace the line, or append it when the key is missing.
set_key() {
    local key="$1" value="$2" escaped
    if grep -q "^$key=" "$INI"; then
        # '|' as the sed delimiter; escape backslashes and '&' in the value for the replacement.
        escaped="$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')"
        sed -i "s|^$key=.*|$key=$escaped|" "$INI"
    else
        printf '%s=%s\n' "$key" "$value" >> "$INI"
    fi
}

# Waits for an extended regex in the log; returns 2 early when the fail regex shows up.
wait_for() {
    local regex="$1" secs="$2" fail="$3" end=$((SECONDS + $2))
    while [ $SECONDS -lt $end ]; do
        grep -qE "$regex" "$LOG" 2>/dev/null && return 0
        grep -qE "$fail" "$LOG" 2>/dev/null && return 2
        sleep 2
    done
    return 1
}

start() {
    [ -x "$GAME/start-server.sh" ] || die "no start-server.sh in $GAME (set PZ_GAME_DIR)"
    running && die "server already running (tools/mp-server.sh stop)"

    if [ "${1:-}" = "--fresh" ]; then
        rm -rf "$CACHE/Saves/Multiplayer/$NAME" "$CACHE/db/$NAME.db"
        echo "fresh world"
    fi

    mkdir -p "$CACHE/Server" "$CACHE/mods/$MOD_ID"
    rsync -a --delete "$REPO/Contents/mods/$MOD_ID/" "$CACHE/mods/$MOD_ID/"
    echo "copied the mod -> $CACHE/mods/$MOD_ID"

    if [ ! -f "$INI" ]; then
        echo "writing a new $INI (the server adds its other defaults on start)"
        printf '# Written by tools/mp-server.sh for manual play-tests.\n' > "$INI"
    fi
    set_key Mods "$MOD_ID"               # plain ids joined with ';', no backslash
    set_key WorkshopItems ""             # non-Steam server: the mod comes from <cache>/mods
    set_key Open true                    # accounts are created on first login
    set_key Public false
    set_key MaxPlayers 8
    set_key PauseEmpty true              # idle time between runs costs nothing

    if [ -f "$SANDBOX" ] && grep -q "IndoorClimateLite = {" "$SANDBOX"; then
        sed -i '/IndoorClimateLite = {/,/^    },/ s/DebugLogging = false/DebugLogging = true/' "$SANDBOX"
        if grep -A100 "IndoorClimateLite = {" "$SANDBOX" | grep -q "DebugLogging = true"; then
            echo "sandbox: IndoorClimateLite.DebugLogging = true"
        fi
    fi

    local args=(-cachedir="$CACHE" -servername "$NAME" -adminusername admin -adminpassword "$ADMIN_PASSWORD")
    if [ "${ICR_SERVER_DEBUG:-1}" = "1" ]; then
        args+=(-debug)
    fi

    rm -f "$FIFO"
    mkfifo "$FIFO"
    : > "$LOG"
    # A new session, so `stop` can end the whole process group. Its shell records its own pid, which is the group id.
    # `tail -f` keeps the fifo open, so the server's stdin never sees end-of-file between commands. The redirections
    # are on the whole subshell, so the server holds none of this script's descriptors: a caller that pipes our
    # output (tools/mp-server.sh start | tee) gets end-of-file when this script exits, not when the server does.
    (cd "$GAME" && exec setsid bash -c "echo \$\$ > '$PGID_FILE'; tail -f '$FIFO' | ./start-server.sh $(printf '%q ' "${args[@]}")") \
        > "$LOG" 2>&1 < /dev/null &
    echo "server '$NAME' starting, log $LOG"

    # 42.21 prints "*** SERVER STARTED ****" and "server is listening on port 16261" when it accepts clients.
    if wait_for "SERVER STARTED|server is listening" 600 "SERVER (STOPPED|FAILED)|Exiting|exiting"; then
        cat <<EOF

Server '$NAME' is ready, cache dir $CACHE
  log:        $LOG  (rotated logs in $CACHE/Logs/)
  config:     $INI
  sandbox:    $SANDBOX
  admin:      admin / $ADMIN_PASSWORD
  clients:    tools/mp-client.sh 1, tools/mp-client.sh 2, ... then Join -> 127.0.0.1, port 16261
  console:    tools/mp-server.sh cmd save
  stop:       tools/mp-server.sh stop
EOF
    else
        tail -20 "$LOG"
        die "server did not start"
    fi
}

stop() {
    if running; then
        printf 'save\n' > "$FIFO"
        sleep 3
        printf 'quit\n' > "$FIFO"
        local pgid
        pgid="$(cat "$PGID_FILE")"
        for _ in $(seq 1 60); do
            pgrep -g "$pgid" -f java >/dev/null || break
            sleep 2
        done
        kill -- "-$pgid" 2>/dev/null || true
    fi
    rm -f "$PGID_FILE"
    echo "server stopped"
}

case "${1:-}" in
    start) shift; start "$@" ;;
    cmd)
        shift
        running || die "server not running"
        printf '%s\n' "$*" > "$FIFO"
        ;;
    stop) stop ;;
    status) running && echo "server running (log $LOG)" || echo "server stopped" ;;
    *) sed -n '2,10p' "$0"; exit 1 ;;
esac
