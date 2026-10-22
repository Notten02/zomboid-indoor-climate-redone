#!/usr/bin/env bash
# Prepares a COPY of a save made with the original mod (Indoor Climate (EHR Addon), mod ID IndoorClimateLiteB42) for
# Indoor Climate Redone, so the takeover of its room temperatures can be tried without risking the real save.
#
#   tools/prepare-migration-save.sh [--dry-run] SAVE_NAME
#
# SAVE_NAME is a folder under ~/Zomboid/Saves/Sandbox (override the Saves/Sandbox folder with SANDBOX_DIR). The
# script:
#   1. copies the whole folder to "<SAVE_NAME>-redone-migration" next to it, and refuses when that already exists;
#   2. rewrites only the copy's mods.txt: the original's entry (IndoorClimateLiteB42, with or without a leading
#      backslash) becomes IndoorClimateRedone. All other lines and the formatting stay as they are. A second original
#      entry, or one next to an existing IndoorClimateRedone entry, is removed instead of renamed, so the mod is
#      listed once.
# The source folder is only read. --dry-run copies nothing and prints the planned mods.txt change as a diff.
# Close the game first: a running game keeps writing to the save.
set -euo pipefail

OLD_ID="IndoorClimateLiteB42"
NEW_ID="IndoorClimateRedone"
DRY_RUN=0
NAME=""

usage() {
    echo "usage: $0 [--dry-run] SAVE_NAME" >&2
    exit 2
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        -h | --help) usage ;;
        -*) echo "unknown option: $arg" >&2; usage ;;
        *) [ -z "$NAME" ] || usage; NAME="$arg" ;;
    esac
done
[ -n "$NAME" ] || usage

case "$NAME" in
    */* | . | .. | "") echo "SAVE_NAME must be a folder name under the Sandbox folder, not a path: $NAME" >&2; exit 2 ;;
esac

SANDBOX="${SANDBOX_DIR:-$HOME/Zomboid/Saves/Sandbox}"
SRC="$SANDBOX/$NAME"
DST="$SANDBOX/$NAME-redone-migration"

[ -d "$SRC" ] || { echo "no such save: $SRC" >&2; exit 1; }
[ -f "$SRC/mods.txt" ] || { echo "$SRC has no mods.txt, so it is not a modded save" >&2; exit 1; }
if [ "$DRY_RUN" -eq 0 ] && [ -e "$DST" ]; then
    echo "refusing: $DST already exists (remove it yourself if you want to start over)" >&2
    exit 1
fi

if ! grep -Eq "^[[:space:]]*mod[[:space:]]*=[[:space:]]*\\\\?$OLD_ID[[:space:]]*,?[[:space:]]*\$" "$SRC/mods.txt"; then
    echo "$SRC/mods.txt does not list $OLD_ID, so there is nothing to migrate." >&2
    exit 1
fi

# Rewrites a mods.txt on stdin to stdout. Keeps the line's indentation, spacing, trailing comma and line ending.
rewrite_mods() {
    awk -v old_id="$OLD_ID" -v new_id="$NEW_ID" '
        # Entry lines look like "    mod = \IndoorClimateLiteB42,". Capture prefix, id and suffix.
        function parse(line) {
            return match(line, /^[ \t]*mod[ \t]*=[ \t]*\\?[^ \t,\r]+/)
        }
        function idOf(line,    id) {
            id = line
            sub(/^[ \t]*mod[ \t]*=[ \t]*\\?/, "", id)
            sub(/[ \t,\r].*$/, "", id)
            return id
        }
        { lines[NR] = $0 }
        END {
            have_new = 0
            for (i = 1; i <= NR; i++) {
                if (parse(lines[i]) && idOf(lines[i]) == new_id) have_new = 1
            }
            for (i = 1; i <= NR; i++) {
                line = lines[i]
                if (parse(line) && idOf(line) == old_id) {
                    if (have_new) continue
                    have_new = 1
                    # Keep everything before the id (indentation, "mod = "; an optional backslash is dropped) and
                    # everything after it (comma, CR).
                    match(line, /^[ \t]*mod[ \t]*=[ \t]*/)
                    prefix = substr(line, 1, RLENGTH)
                    suffix = line
                    sub(/^[ \t]*mod[ \t]*=[ \t]*\\?[^ \t,\r]+/, "", suffix)
                    line = prefix new_id suffix
                }
                print line
            }
        }
    '
}

PLANNED="$(mktemp)"
trap 'rm -f "$PLANNED"' EXIT
rewrite_mods < "$SRC/mods.txt" > "$PLANNED"

if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry run: nothing is copied. Planned change to mods.txt of $DST:"
    diff -u --label "$SRC/mods.txt" --label "$DST/mods.txt" "$SRC/mods.txt" "$PLANNED" || true
    exit 0
fi

# -a keeps timestamps; nothing under $SRC is modified.
cp -a -- "$SRC" "$DST"
cp -- "$PLANNED" "$DST/mods.txt"

echo "copied $SRC"
echo "     -> $DST"
echo "mods.txt of the copy changed:"
diff -u --label "$SRC/mods.txt" --label "$DST/mods.txt" "$SRC/mods.txt" "$DST/mods.txt" || true
cat <<EOF

Next steps (the original save was not touched):
  1. Deploy the current mod (tools/deploy-dev.sh) and make sure the original is not enabled for this save.
  2. Start the game and load "$NAME-redone-migration" from the Sandbox load list. Do not load the original.
  3. Look for "[IndoorClimateRedone] took over N building states that <player> saved with Indoor Climate" in
     ~/Zomboid/console.txt. N is the number of map buildings the character had visited with the original.
  4. Walk into a building you heated with the original: it should start at the temperature it had, not at the
     outdoor air plus 2 C. Player-built rooms start again (expected).
  5. Placed heaters and fans keep whether they were on and their propane tank.
  6. Save and reload once: the line must not appear again (every taken-over building now has its own state).
EOF
