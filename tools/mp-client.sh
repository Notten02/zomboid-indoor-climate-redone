#!/usr/bin/env bash
# Starts game client N against tools/mp-server.sh, in the background, with its own cache dir (<root>/client<N>) and
# its own copy of the mod. For manual play-tests: log in and play by hand.
#
#   tools/mp-client.sh 1          client 1 (log in as admin), then tools/mp-client.sh 2, 3 for the other players
#
# Settings (environment variables, all optional):
#   ICR_MPTEST_DIR     root of the test cache dirs          default: <repo>/.cache/mptest (same as mp-server.sh)
#   ICR_CLIENT_MODE    java | launcher                      default: java
#       java:     the JVM directly with the stock arguments of ProjectZomboid64.json and -Dzomboid.steam=0, without
#                 any Java agent. Verified on 42.21 against the non-Steam server.
#       launcher: ProjectZomboid64 -nosteam, as projectzomboid.sh starts the game. It reads ProjectZomboid64.json,
#                 including any Java agent configured there. Not verified: if -nosteam does not override the JSON's
#                 -Dzomboid.steam=1, the connection to the non-Steam server fails at once.
#   ICR_CLIENT_XMX     client heap for java mode            default: 3072m
#   ICR_CLIENT_DEBUG   1 passes -debug (Lua console, F11)   default: 0. The server kicks a -debug client unless its
#                      account has the ConnectWithDebug capability.
#   PZ_GAME_DIR        the game's projectzomboid folder     default: the Steam library install under /mnt/games
#
# Every start the client gets copies of the mod in <cache>/mods and <cache>/Workshop (the same files as the server, or
# the server refuses the client for a checksum mismatch), and the mod is enabled in <cache>/mods/default.txt so its
# Lua also runs on the main menu.
set -euo pipefail

N="${1:-}"
if ! [[ "$N" =~ ^[0-9]+$ ]]; then
    echo "usage: tools/mp-client.sh N   (N = 1, 2, 3, ...)" >&2
    exit 1
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${ICR_MPTEST_DIR:-$REPO/.cache/mptest}"
GAME="${PZ_GAME_DIR:-/mnt/games/Steam/steamapps/common/ProjectZomboid/projectzomboid}"
MODE="${ICR_CLIENT_MODE:-java}"
MOD_ID=IndoorClimateRedone
CACHE="$ROOT/client$N"
OUT="$CACHE/stdout.log"

if [ ! -x "$GAME/ProjectZomboid64" ]; then
    echo "no ProjectZomboid64 in $GAME (set PZ_GAME_DIR)" >&2
    exit 1
fi

mkdir -p "$CACHE/mods/$MOD_ID"
ZOMBOID_DIR="$CACHE" "$REPO/tools/deploy-dev.sh"
rsync -a --delete "$REPO/Contents/mods/$MOD_ID/" "$CACHE/mods/$MOD_ID/"
printf 'VERSION = 1,\n\nmods\n{\n    mod = %s,\n}\n\nmaps\n{\n}\n' "$MOD_ID" > "$CACHE/mods/default.txt"
# Without this marker the first launch of a fresh cache dir empties default.txt (the Build 42 mod reset).
printf 'If this file does not exist, default.txt will be reset to empty (no mods active).\n' \
    > "$CACHE/mods/reset-mods-42_00.txt"
[ -f "$CACHE/options.ini" ] || printf 'fullScreen=false\nwidth=1280\nheight=720\nborderless=false\nframeRate=30\n' \
    > "$CACHE/options.ini"

GAME_ARGS=(-nosteam -cachedir="$CACHE")
if [ "${ICR_CLIENT_DEBUG:-0}" = "1" ]; then
    GAME_ARGS+=(-debug)
fi

cd "$GAME"
export LD_LIBRARY_PATH="$GAME/natives:$GAME:$GAME/jre64/lib:${LD_LIBRARY_PATH:-}"
export PATH="$GAME/jre64/bin:$PATH"
PRELOAD="${LD_PRELOAD:-}:libjsig.so:libPZXInitThreads64.so"

case "$MODE" in
    java)
        XMODIFIERS= LD_PRELOAD="$PRELOAD" setsid "$GAME/jre64/bin/java" \
            -cp ".:projectzomboid.jar" \
            -Djava.awt.headless=true \
            --enable-native-access=ALL-UNNAMED \
            --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED \
            -Xmx"${ICR_CLIENT_XMX:-3072m}" \
            -Dzomboid.steam=0 \
            -Dzomboid.znetlog=1 \
            -Djava.library.path=natives/ \
            -Djava.security.egd=file:/dev/./urandom \
            -XX:+UseZGC \
            -XX:-OmitStackTraceInFastThrow \
            zombie/gameStates/MainScreenState "${GAME_ARGS[@]}" > "$OUT" 2>&1 < /dev/null &
        ;;
    launcher)
        XMODIFIERS= LD_PRELOAD="$PRELOAD" setsid ./ProjectZomboid64 "${GAME_ARGS[@]}" > "$OUT" 2>&1 < /dev/null &
        ;;
    *)
        echo "ICR_CLIENT_MODE must be java or launcher, not $MODE" >&2
        exit 1
        ;;
esac
PID=$!

if [ "$N" = "1" ]; then
    LOGIN="admin / ${ICR_ADMIN_PASSWORD:-admin} (the server's admin account)"
else
    LOGIN="any new name and password, e.g. player$N / player$N (the server is open)"
fi

cat <<EOF
Client $N started ($MODE mode), pid $PID, cache dir $CACHE
  game log:   $CACHE/console.txt
  stdout:     $OUT
  connect:    Join -> server 127.0.0.1, port 16261
  log in as:  $LOGIN
  stop:       kill $PID
EOF
