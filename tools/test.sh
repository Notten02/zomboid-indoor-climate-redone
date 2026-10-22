#!/usr/bin/env bash
# Runs the offline checks: the Kahlua subset check, the game API check (tools/check-api.lua), then the busted specs
# under Lua 5.1. The two static checks cover the shipped mod (Contents) and the dev-only E2E test mod (tests/e2e),
# since both run in the game.
# Extra arguments go to busted, e.g. `tools/test.sh --filter=docs`.
set -euo pipefail
cd "$(dirname "$0")/.."

for cmd in lua5.1 luac5.1; do
    command -v "$cmd" >/dev/null || { echo "missing $cmd (Arch: pacman -S lua51)" >&2; exit 1; }
done
if ! lua5.1 -e 'require("busted.runner")' 2>/dev/null; then
    echo "busted for Lua 5.1 not found (Arch: pacman -S lua51-busted)" >&2
    exit 1
fi

for dir in Contents tests/e2e; do
    lua5.1 tools/check-kahlua.lua "$dir"
    lua5.1 tools/check-api.lua "$dir"
done
lua5.1 tools/busted51.lua "$@"
