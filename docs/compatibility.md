# Compatibility

Indoor Climate Redone needs no other mod and can sit anywhere in the load order. Its hooks into other mods are
installed when the game starts, not when its files load.

| Mod | Status |
|---|---|
| Indoor Climate (EHR Addon), mod ID `IndoorClimateLiteB42` | **Do not enable both.** This is the original. |
| Extensive Health Redone | Supported. Reads the room air on the server. |
| Extensive Health Rework Evolved | Not tested. Reads the same API. |
| Lua Digital Watch UI | Supported. The watch shows the room air. |
| Unseasonal Weather | Supported. Its clock shows the room air. |
| Realistic Temperature | **Indoor Climate Redone switches itself off.** |

## Indoor Climate (EHR Addon), the original

- Workshop `3772549209`, mod ID `IndoorClimateLiteB42`, by Frozen_Heart.
- Indoor Climate Redone is a rewrite of it and replaces it. Both use the same global API, item IDs and sandbox
  option names, so they cannot run together. `mod.info` marks the original as incompatible.
- Switching over keeps your items, sandbox settings and the temperatures of map buildings. See
  [changes-from-original.md](changes-from-original.md).

## Extensive Health Redone

- Optional. Without it, the mod still works: warm rooms warm your character through the game's own air.
- With it, its heat and cold meters read the room air from this mod (the player's sample, `airC`). That is how cold
  rooms and the fan's cooling reach your character, which the game alone cannot do (see
  [known-limitations.md](known-limitations.md)).
- In multiplayer, Extensive Health Redone runs its health model on the server and reads the sample there. Indoor
  Climate Redone simulates rooms on the server, so the value is the real one, not a client's report.
- With the original Indoor Climate instead of this mod, a dedicated server has no room air to read: the original
  works out rooms on each client only. Single player is unaffected.

## Extensive Health Rework Evolved

- Workshop `3726328119`, by Frozen_Heart. The original Indoor Climate was made for it and named it a requirement.
  Indoor Climate Redone does not.
- It reads the same `IndoorClimateLite` API, and the `UI_ICL_IndoorAir` and `UI_ICL_OutdoorAir` texts it shows are
  kept for it. Not tested together.

## Lua Digital Watch UI

- Workshop `3676456221`.
- Indoors in a simulated room the watch shows the room air (with the devices near you); elsewhere it shows what it
  showed before. The mod sets both the watch's temperature reader and its temperature override, and puts them back
  if another mod replaces them.
- Hooked at game start, so the load order does not matter (the original had to load last).

## Unseasonal Weather

- Its own digital clock gets the same temperature reader as Lua Digital Watch UI, as in the original.

## Realistic Temperature

- Mod IDs `RC_RealisticColdMod` and `RealisticTemperature`.
- It models indoor temperature itself. While it is enabled, Indoor Climate Redone does not simulate rooms, places no
  bridge heat source and its API reports itself inactive, as the original did. The devices still work, and the
  heaters still warm the game's own air near them.
