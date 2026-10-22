# Design: server-authoritative room simulation

The room temperature simulation runs on the server. Single player runs the same code in one process.

The original worked out rooms on each player's client. Two players in one house could then see different
temperatures, a server-side mod could not read them, and in Build 42.21 the game works out body warmth on the server,
which never saw the original's heat sources. A Build 42 dedicated server can read everything the building model
needs, store room state in world data and send each player their own sample, so it runs the simulation for everyone.

## What a Build 42 dedicated server can read

| Area | Behaviour on a Build 42.21 dedicated server |
|---|---|
| Room and building lookup | `square:getRoomDef()`, `getRoom()`, `getBuilding()` and `BuildingDef` all work. The room key (`vanilla:<RoomDef ID>`) and the building key (`building:x..:y..:w..:h..`) are the same on the server and the client. |
| Loaded area | Squares exist up to about 70 to 100 tiles from a player (at z 0) and not further. A building can be scanned only while a player is near it. |
| Doors, windows, barricades | Doors, windows, window frames, barricades and smashed or open state are read the same as on the client. `IsoGridSquare:getDoor` and `getWindow` take an edge in 42.21, not the boolean the original passed; the scan reads the square's object lists instead. |
| Player-built rooms | `getIsoWorldRegion()` reports `isPlayerRoom`, `isFullyRoofed` and the size. The region ID differs between the server and a client. |
| World regions in map buildings | The server returns no world region for squares inside a map building, while a client does. Map rooms are found through `RoomDef` first, so this does not matter. |
| Power | `getWorld():isHydroPowerOn()` works. `square:haveElectricity()` reports generator power only (it is `false` while the grid is on); `square:hasGridPower()` is the grid check. |
| Climate | `getClimateManager():getTemperature()` and `getAirTemperatureForSquare()` both work. |
| World data | Global ModData (`ModData.getOrCreate`) is saved with the world and restored after a restart. On a restart `OnInitGlobalModData` passes `isNewGame = true` for a world that already exists. |
| Sync | `sendServerCommand(player, ...)` delivers nested tables to that player, and `sendClientCommand` replies come back. |
| Object events | Server-side changes (door toggle, barricade, smash, new walls) fire no `OnObjectAdded`, `OnObjectAboutToBeRemoved`, `OnTileRemoved` or `OnDestroyIsoThumpable` on the server. Loading map chunks fires thousands of `OnObjectAboutToBeRemoved` and `OnTileRemoved` events. |
| Body warmth | The server works out body warmth from its own air at the player, and the client follows it. A heat source placed only on the client warms the client's air but not the character. |

## Design rules

- **Scan on the server, only near players.** Scan buildings that are inside the loaded area, in budgeted chunks. A
  square that does not exist yet means the scan is incomplete, so retry it later.
- **Refresh by re-reading, not by events.** Object events do not report server-side changes and are very noisy while
  chunks load. Keep the list of openings from the scan and read their state again on every update, which is cheap.
  Rescan the building envelope on a timer, as the original does every 6 game hours, or when a player enters a
  building whose scan is out of date.
- **Room keys.** Vanilla room and building keys are the same as the original's, and they are the same on server and
  client. State saved by the original for vanilla rooms can therefore be imported. Player-built room keys come from
  world region IDs, which differ between machines, so that state cannot be imported. Those rooms start fresh, which
  is the behaviour the original already has when a player rebuilds a room.
- **Power.** Rooms use grid power (`isHydroPowerOn`), as in the original. Device power checks must use
  `hasGridPower()` or `isHydroPowerOn()` for the grid and `haveElectricity()` for generators.
- **Do not trust `isNewGame`.** Detect a new world from the contents of the mod's own world data, for example a missing
  version field.
- **Buildings far away.** Buildings outside the loaded area are not simulated until a player enters them. They
  start at outdoor temperature plus the unvisited offset.

## How it is built

- `shared/IndoorClimateRedone/Game/Places.lua` describes the zone and room of a square (the original's descriptor
  rules and keys). `Openings.lua` reads doors, windows and frames into the plain opening tables the model weighs.
- `server/IndoorClimateRedone/Envelope.lua` scans a zone in chunks of at most 300 squares per zone and update, and at
  most 1,500 squares per update for the whole server. A map building is scanned over its `BuildingDef` bounds on
  every floor its rooms are on, a player-built room by flooding out from the square a player entered it from. The
  state of every known opening and inner door is read again on each update. A scan is redone after 6 game hours, at
  once when a known object has left its square, and after 15 game minutes when part of the building was not loaded.
  Room edges are sorted by key, so rooms share heat in the same order every time.
- `server/IndoorClimateRedone/Climate.lua` steps each zone with a player in it every `UpdateMinutes` (1 by default),
  and at once when a player walks into another room or zone. A walk between floors of one building teaches it the
  stairs. Zones nobody is in are not stepped; they catch up when someone returns.
- `shared/IndoorClimateRedone/Store.lua` keeps the zone states and the grid power record in global ModData under
  `IndoorClimateRedone`, with a version field. At most 1,024 zones are kept, the least recently seen are dropped
  first, and a dropped zone starts again as unvisited.
- Rooms reach the powered target on grid power only, as in the original; generator power is for devices.
- Map building states saved by the original mod in a player's data are taken over the first time that player is
  seen, for every building that has no state yet. The original data is left in place. Player-built room states are
  not taken over.
- The server sends each player only their own room sample (`shared/IndoorClimateRedone/Sync.lua`,
  `server/IndoorClimateRedone/Sender.lua`): when they first have one, when they change room or zone, when power, open
  doors or windows change, when a temperature has moved by 0.2 C since the last send, and at least every 30 real
  seconds. When the player leaves the simulated rooms the server sends a clear once. A client sends a hello when its
  player is created (joining or reconnecting), and the server answers at once. Each message carries the player's
  online ID, so a client with more than one local player can tell them apart.
- A client (`client/IndoorClimateRedone/`) keeps the samples it received. It stops using one as soon as its player
  is in a vehicle or outside the rooms, without waiting for the server's clear.
- The public API is the global `IndoorClimateLite` (`shared/IndoorClimateRedone/Game/Api.lua`), with the
  original's functions and sample fields. It answers from the simulation on a server and in single player, and from the
  received samples on a client, so a server-side mod reads the same room air the player's client shows. On a
  client, `getTemperatureForSquare` knows only the room the player is in; any other square gets the game's own air.
- The native bridge is a heat source of radius 1 on the player's square, set so that the game's air there matches the
  room when the room is more than 0.25 C warmer than the game's air. The original placed it on the player's client
  only. In multiplayer the game works out body warmth on the server (see above), so it is placed there too: each
  client places it for its local players, a dedicated server for every online player. The simulation reads the
  game's air with the mod's own heat sources taken out, so a room cannot warm itself through its bridge.

## Devices

The four devices (cheap, premium and propane heaters and the standing fan) keep the original's item IDs, figures and
rules; `shared/IndoorClimateRedone/Heater.lua` holds them.

- **The server owns device state.** A device is an item placed on the ground, and its state stays in the item's mod
  data under the original's field names, so devices in existing saves keep it. A client's context menu sends a
  command; the server (`server/IndoorClimateRedone/Appliances.lua`) checks the player is within 3 tiles on the same
  floor and that the device can run, switches it, and sends the new state to every client. In single player the menu
  calls the same code directly.
- **Fuel and switching off.** Every game minute the server checks each switched-on device. It switches off a device
  that lost its electricity or ran out of propane, burns propane (0.025 of a tank an hour) and, while the grid is off,
  takes generator fuel from the nearest running generator within 20 tiles and 3 floors (the fan 0.20 L/h, heaters the
  `HeaterGeneratorFuelPerHour` option). A generator that runs dry switches off with its devices. Time missed while a
  device was unloaded counts up to `MaxElapsedHours`.
- **Finding devices.** Object events do not report server-side changes (see above), so the server looks
  for switched-on devices around players every 10 game minutes and on every square that loads. A device that was
  switched on, picked up and put down elsewhere comes back off; the original left it on.
- **The sample.** A device changes the air a player feels, not the room's own temperature, as in the original: the
  sample's `airC` is the room plus the change from the switched-on devices near the player's square, weakened by the
  room's leaks, and `baseRoomC` is the room. The server works that part out again whenever a player moves to another
  square or a device changes state, so a server-side mod reads the same value the client shows.
- **Game heat sources.** As in the original, a switched-on heater (not the fan) places a game heat source, so the
  game's own air near it warms. It is placed on the clients near it and, since the server works out body warmth, on
  a dedicated server for every online player near it. The room simulation reads the game's air with every one of the
  mod's heat sources taken out.
- A client keeps device states in step from the server's messages, from the squares it loads and from a look around
  its players every game minute; a client that joins is sent the switched-on devices near it.
- Loot (`server/IndoorClimateRedone/Loot.lua`) uses the original's container lists and weights, and the extra roll in
  warehouses and storage units that runs after the game has filled the container.
- The generator info window lists the devices a running generator powers and adds their draw to its total.
- Lua Digital Watch UI shows the room air through its temperature reader and override; the hooks are installed at
  game start and kept up, so the load order does not matter.

## Cost

Measured on a dedicated server with one client:

- A full scan of a single-storey house (77 squares) takes 1 to 9 ms the first time and about 1 ms after that.
  Re-reading the state of its 11 openings takes 0.01 to 0.03 ms.
- Ten buildings near a player (about 1,800 squares) take 25 to 29 ms to scan in all, at most 8 ms for one building.
- Stepping a zone takes about 0.16 ms, so stepping every occupied zone each game minute is cheap.

`tests/e2e/README.md` describes the automated tests that run on a dedicated server.
