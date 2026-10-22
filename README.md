# Indoor Climate Redone

Room air temperature for Project Zomboid **Build 42.21**. Buildings hold heat, open doors and broken windows let it
out, a power cut lets a warm house cool down over hours, and placeable heaters and a fan change the air near them.

A from-scratch rewrite of **Indoor Climate (EHR Addon)** by **Frozen_Heart**, the original author
([Workshop 3772549209](https://steamcommunity.com/sharedfiles/filedetails/?id=3772549209)). The gameplay follows the
original; the code is new, and the server runs the simulation, so it works in multiplayer. The original was made for
Extensive Health Rework Evolved; this rewrite is an addon for its rewrite, **Extensive Health Redone**, whose heat and
cold meters read the room air. It also works on its own.

## What it does

- Every room of a building has its own temperature, saved with the world. With grid power rooms head for 22 C;
  without it they drift toward the outdoor air, slowly when sealed and up to 12 times faster with doors and windows
  open or broken. Barricades help. Rooms share heat through passages, doors, walls and stairs.
- Unvisited buildings start near the outdoor temperature. Only buildings with a player in them are simulated.
- Four devices from the original: Cheap Heater, Premium Heater, Standing Fan (on grid or generator power) and
  Propane Heater (on vanilla propane tanks), with loot, context menus and generator fuel use.
- Warm rooms warm your character through the game's own air. It never writes body temperature.
- The global `IndoorClimateLite` API gives other mods the room air, on the server and on clients.
- Lua Digital Watch UI shows the room air.

The details are in [docs/player-guide.md](docs/player-guide.md).

## Compatibility with the original

- Mod ID `IndoorClimateRedone`. It cannot be enabled together with the original (`IndoorClimateLiteB42`).
- The item module `IndoorClimateLite`, the item IDs, the sandbox option names (`IndoorClimateLite.*`) and the global
  `IndoorClimateLite` API are kept, so placed devices, server configs and mods that read the API carry over. The
  room temperatures of map buildings are taken over from the original's save data.

What changed is in [docs/changes-from-original.md](docs/changes-from-original.md), other mods in
[docs/compatibility.md](docs/compatibility.md). All documents are listed in [docs/README.md](docs/README.md).

## Installing

**Players:** subscribe on the Steam Workshop, enable *Indoor Climate Redone* in the mod list
and disable the original. Needs Build 42.21 or newer. Optional: Extensive Health Redone, Lua Digital Watch UI.

**From source:** `tools/deploy-dev.sh` copies `Contents/` into `~/Zomboid/Workshop/IndoorClimateRedone/`; enable the
mod in the game's mod list. Run it again after each change.

**Bug reports:** the issue tracker of this repository. Include your `console.txt` (on a server, its log too).

## Repository layout

```
Contents/mods/IndoorClimateRedone/   the mod (the repo root is the Workshop item folder)
  42/mod.info                        mod metadata
  42/icon.png, 42/poster.png         mod list icon and poster (tools/make-release-art.py)
  42/media/                          Lua, item scripts, sandbox options, translations
  common/media/                      models and textures
tests/                               busted specs (offline, never shipped)
tests/e2e/                           a test mod for automated runs on a dedicated server (never shipped)
tools/                               dev scripts (tools/lib: helpers shared by tools and tests)
docs/                                player, compatibility, API and design documents, the Workshop text
preview.png                          Workshop thumbnail (256x256), copied next to Contents/ when uploading
```

## Code layout

```
42/media/lua/shared/IndoorClimateRedone/        pure model: Config, Model, Leak, Rooms, Heater, Propane, Store, Sync
42/media/lua/shared/IndoorClimateRedone/Game/   game adapters shared by server and client: Places, Openings, Power,
                                                Devices, the API, the bridge and device heat sources
42/media/lua/server/IndoorClimateRedone/        the simulation: building scan, rooms, devices, loot, sending samples
42/media/lua/client/IndoorClimateRedone/        received samples, context menus, the generator window, the watch
```

- The pure model calls no game API. Time and randomness are passed in, so the specs test it directly.
- `require` paths leave out the side folder, so every file has a name of its own across shared, client and server.
- The server (or the single-player game, which runs the same code) owns the room temperatures and the devices.
  Clients receive their own room's sample and send menu choices. `docs/design/server-authoritative-rooms.md`
  explains the design and what a Build 42 server can and cannot read.

## Development

Requirements (Arch / CachyOS): `pacman -S lua51 lua51-busted lua-language-server`.
Lua 5.1 is used because it is closest to Kahlua, the game's Lua VM.

| Task | Command |
|---|---|
| Run the checks and tests | `tools/test.sh` |
| Download the game's type stubs (once per clone) | `tools/fetch-umbrella.sh` (into `.cache/`, not committed) |
| Type-check with LuaLS | `lua-language-server --check=.` (after `tools/fetch-umbrella.sh`) |
| Load the working copy in game | `tools/deploy-dev.sh` |
| Manual multiplayer test | `tools/mp-server.sh`, `tools/mp-client.sh` |
| Try a save made with the original | `tools/prepare-migration-save.sh [--dry-run] SAVE_NAME` (works on a copy) |
| Regenerate the icon, poster and Workshop preview | `python3 tools/make-release-art.py` (needs Python 3 and Pillow) |

`tools/test.sh` first runs `tools/check-kahlua.lua`, which rejects Lua the game cannot run (anything `luac5.1 -p`
rejects, and `io`, `os`, `debug`, `load`, `next` and 5.2+ library functions). Then `tools/check-api.lua` checks that
every method the mod calls still exists in the game API, against the stubs. Then the busted specs run;
`tests/support/fake_game.lua` and `fake_world.lua` stand in for the game. `tests/e2e/README.md` describes the
automated dedicated-server tests.

## Credits and licence

- Original design, devices, models, textures, icons and translations: **Frozen_Heart**, who opened the mod to the
  community. See `CREDITS.md` and `ASSETS.md`.
- Code: MIT (`LICENSE`). Reused content is not covered by the MIT licence; see `ASSETS.md`.
- The icon, poster and Workshop preview are new, drawn by `tools/make-release-art.py`, and covered by the MIT licence.
