# Changes from the original

What is different from Indoor Climate (EHR Addon) v0.12.2 by Frozen_Heart, for players and server admins. The
gameplay is meant to stay the same: the room rules, the numbers, the devices and the sandbox defaults are the
original's. The code is new.

## Switching over

1. Back up your save.
2. Disable Indoor Climate (EHR Addon) (`IndoorClimateLiteB42`) and enable Indoor Climate Redone
   (`IndoorClimateRedone`). They cannot run together.
3. On a server, change `IndoorClimateLiteB42` to `IndoorClimateRedone` in `Mods=`, and the original's Workshop ID
   `3772549209` to this mod's in `WorkshopItems=`.

What carries over:

- **Items and devices.** The item module `IndoorClimateLite` and the four item IDs are the same. A placed device
  keeps whether it is on, its propane tank and the tank's fill, which are kept in the item under the original's
  names.
- **Sandbox settings.** Every option keeps its name, range and default (`IndoorClimateLite.*`).
- **Room temperatures of map buildings.** The original kept them in each player's data. The first time the server
  sees a player, it takes over the buildings that player's data holds, for every building it has no temperature for
  yet. The original's data is left in place.
- **Other mods.** The global `IndoorClimateLite` API keeps its functions and sample fields (see [api.md](api.md)).

What does not:

- **Player-built rooms** start again like unvisited buildings. Their identities in the original's data came from the
  client and differ on a server.

## Changed

- **The server runs the simulation.** The original worked out rooms on each player's client, so two players in one
  house could see different temperatures, and a server-side mod could not read them. Now the server keeps one
  temperature per room for everyone, saves it with the world, and sends each player their own room's value. Single
  player is the same as before.
- **Warmth reaches your character in multiplayer.** In Build 42.21 the game works out body warmth on the server. The
  original placed its heat sources (the bridge and the heaters) on the client only, so in multiplayer the server
  never saw them. They are now placed on the server as well.
- **A client knows only its own room.** On a multiplayer client, `getTemperatureForSquare` returns the simulated
  temperature only for the room its player is in; elsewhere it returns the game's own air. The server knows every
  room.
- **A device picked up while switched on comes back off.** The original left it on wherever it was put down.
- **Load order no longer matters.** The original had to load last for the Lua Digital Watch UI support. The watch is
  now hooked when the game starts and kept hooked.
- **No required mod.** The original described Extensive Health Rework Evolved as a hard requirement. Indoor Climate
  Redone works alone, and with Extensive Health Redone.
- **More buildings are remembered.** The original kept up to 64 zones per player. The world now keeps up to 1,024,
  dropping the ones not seen for the longest time first.
- **A building at the edge of the loaded map** is scanned again after 15 game minutes, so its missing squares are
  picked up once a player gets closer. Otherwise a building is scanned again every 6 game hours, as before.
- **Version.** `IndoorClimateLite.VERSION` and the sample's `version` are this mod's version, not 0.12.2.
- **Texts.** Six sandbox tooltips say more: the simulation stays off with Realistic Temperature, the server runs it in multiplayer, the fan's generator fuel use is fixed at 0.20 L/h,
  open doors and windows weaken heaters and fans too, the bridge is placed on the server in multiplayer, and debug
  logging also reports the simulation's cost.

## Fixed

- **The building scan works on Build 42.21.** In 42.21, `IsoGridSquare:getDoor` and `getWindow` no longer take the
  boolean the original passed. The scan reads doors and windows from the square's objects instead.

## Unchanged, though the original's README says otherwise

- The original's README describes the default update interval as 10 game minutes. Its sandbox default, which the
  game uses, has always been 1 minute, and still is.
- The README also describes carrying the temperature across a direct walk between two player-built rooms. Version
  0.12.2 does not do this, and neither does Redone: each player-built room is its own zone.

The original's texts are archived in [original-author-guides/](original-author-guides/).
