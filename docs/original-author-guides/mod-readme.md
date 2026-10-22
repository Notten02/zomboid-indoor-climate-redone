# Mod README (Indoor Climate Lite)

> The `README.md` that ships inside the original mod (`mods/IndoorClimateLite/README.md`, v0.12.2), by Frozen_Heart.
> Archived on 2026-10-22, word for word; only the heading levels are moved down one. It is the most detailed
> description of how the original simulates rooms, and is kept as the behaviour reference for this rewrite. It
> describes the original, not Indoor Climate Redone: for example, the original runs on each client, while Redone runs
> the simulation on the server. See `docs/changes-from-original.md`.

---

## Indoor Climate Lite

Lightweight indoor-temperature simulation for Project Zomboid Build 42.

The mod keeps lightweight thermal states for the rooms of the map building
currently occupied by each local player. A broken/open exterior window affects
its own room first. Heat then moves between rooms through cached passages,
internal doors, walls, and learned stair transitions. Sealed powered rooms
target 22 C. After the power goes out, rooms retain heat and drift toward the
outdoor temperature over time.

An unvisited map building has no background simulation record. On first entry,
it starts at the current outdoor temperature plus the configurable unvisited
building buffer (2 C by default, or 0 C for an exact outdoor-temperature
start). This lazy initialization does not scan or update unloaded buildings.

### Electric space heater

Version 0.7 adds a placeable electric space heater using the mod's own
`Heater2` model and texture. Right-click it in an inventory and choose
**Install Heater**, then use the placed object's context menu to turn it on or
off. It can only be turned on when its square has grid or generator power and
automatically switches off after losing power.

When supplied by a generator, each active heater adds 0.04 litres per in-game
hour to its fuel use by default (about one litre per 25 hours). The value is
configurable from 0 to 0.25 L/h. Grid power does not consume generator fuel.

An active heater creates a native heat source with a six-tile radius. ICL also
adds the same distance-faded local warmth to its public temperature sample, so
EHR and Lua Digital Watch UI see the heated air. The underlying room state is
kept separate, preventing a local heater from instantly warming an entire
building through the room cache.

### What it deliberately does not do

- no writes to body/core temperature;
- no `BodyDamage` or sickness changes;
- no `Thermoregulator.setSimulationMultiplier` override;
- no clothing, insulation, or wind-resistance edits;
- no food or vehicle changes;
- no pathfinding, heater network, or per-frame building scan;
- no server-wide temperature network.

The optional vanilla bridge uses a radius-one `IsoHeatSource` on the local
player's square only when the simulated room is warmer than the temperature
already reported by Build 42. Vanilla thermoregulation remains responsible for
the character unless EHR consumes the public ambient-temperature API.

### Extensive Health Rework compatibility

EHR builds with the native Indoor Climate Lite bridge use this mod as their
ambient-temperature source. ICL still does not write body temperature: EHR owns
that calculation, applies clothing/wetness/exertion through its existing model,
and mirrors the resulting core temperature to the game. The EHR temperature tab
shows the simulated indoor air value and the outdoor comparison.

When **Lua Digital Watch UI** is enabled, its temperature field also shows the
current ICL indoor temperature. The integration uses the watch mod's resolver API,
samples at most twice per second, and falls back to the original watch
temperature outdoors and in vehicles.

In multiplayer, ICL remains client-local and adds its current sample to EHR's
existing environmental snapshot. This does not add another network loop or
server-side building scan.

### Performance model

- one persistent building record containing lightweight room states, or one
  state per player-built room;
- simulation every 10 in-game minutes by default and once on thermal-zone entry;
- map buildings build one cached room graph, exterior-opening list, and internal
  connection list; work is limited to 300 building-bound cells per in-game
  minute, so very large buildings are scanned in small resumable chunks;
- after that initial scan, scheduled updates inspect only cached room nodes,
  connections, and openings;
- the envelope is rebuilt after a relevant object is added/removed and at most
  once every 6 in-game hours as a safety refresh;
- while a building envelope is still being built, the nearby radius-5 scan
  remains active as a temporary fallback;
- ordinary `OnPlayerUpdate` frames only compare the current square and room;
  walking between rooms never starts another cell scan;
- at most 64 cached thermal-zone records per player and 24 runtime building
  envelopes by default.

### Installation

Copy the `IndoorClimateLite` directory to:

`C:\Users\<you>\Zomboid\mods\IndoorClimateLite`

Enable **Indoor Climate Lite** for a Build 42 save. Do not enable it together
with Realistic Temperature; Indoor Climate Lite disables itself when it detects
that mod.

### Limitations

Build 42 exposes heat sources as local heating only: they can raise a square's
native air temperature but cannot lower it. When the simulated room is colder
than the native air, the public API and debug log report the simulated value,
but vanilla thermoregulation still sees its own baseline. EHR compatibility
solves this at the health-model layer; without EHR, ICL deliberately does not
work around it by writing body temperature.

Building state is client-local in multiplayer by design. This avoids network
traffic and server scans, but two clients entering the same building for the
first time can temporarily have slightly different cached temperatures.

Changing the unvisited-building buffer affects only buildings that do not yet
have a saved Indoor Climate Lite state. Previously visited buildings keep their
temperature history.

Map buildings use the game's own `BuildingDef`. Its bounds are scanned once in
bounded chunks to cache thermal rooms, exterior doors/windows, and connections
between rooms; this also works when a map returns an empty runtime room-square
list. Permanent open passages equalize quickly, open internal doors exchange
heat quickly, closed doors and walls exchange heat slowly, and a cross-floor
transition teaches the runtime cache about a stair connection.

Project Zomboid exposes player-built structures as separate roofed regions
rather than the same map building definition. To avoid a costly flood-fill, ICL
smoothly carries the current temperature across a direct transition between
player-built rooms. If the player walks outdoors between them, they remain
separate zones.

Player-built room identifiers can change when the structure is rebuilt. A
rebuilt zone starts from the vanilla indoor temperature unless it is entered
directly from another player-built indoor zone.

### Public API

The global `IndoorClimateLite` table provides:

- `getTemperatureForPlayer(player)`
- `getTemperatureForSquare(square, player)`
- `getTemperatureSample(player)`
- `getRoomDescriptor(square)`
- `refreshConfig()`
- `isActive()`

`getTemperatureSample()` returns `airC`, `targetC`, `outdoorC`, `vanillaAirC`,
`indoors`, `powered`, `roomKey`, `leakScore`, `openDoors`, and `openWindows`.
For map buildings, `roomKey` identifies the current thermal room and
`buildingKey` identifies the shared building record. Map-building samples also
expose `envelopeComplete`, `cachedOpenings`, `thermalRoomCount`,
`thermalEdgeCount`, `envelopeSquaresScanned`, and
`envelopeBuildingSquares` for diagnostics. The sample includes `source`,
`version`, and `active` so compatibility consumers can reject disabled or
conflicting samples.
