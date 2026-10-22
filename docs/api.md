# The `IndoorClimateLite` API

For mod authors. Indoor Climate Redone fills the global table `IndoorClimateLite` with the functions and sample
fields of the original Indoor Climate Lite, so a mod written for the original works unchanged. The code is
`shared/IndoorClimateRedone/Game/Api.lua`.

The table exists in every Lua VM (dedicated server, its clients, single player) once the shared files have loaded.
No function errors on a `nil` player or square.

## Functions

| Function | Returns |
|---|---|
| `IndoorClimateLite.isActive()` | `true` while the simulation runs: the sandbox option is on and Realistic Temperature is not enabled |
| `IndoorClimateLite.getTemperatureSample(player)` | a copy of the player's sample (below); safe to keep or change |
| `IndoorClimateLite.getLiveTemperatureSample(player)` | the sample itself, not a copy (read only); `nil` outside the simulated rooms, while the mod is inactive, and on a client before the server's first sample |
| `IndoorClimateLite.getTemperatureForPlayer(player)` | the air the player feels, in C (the sample's `airC`) |
| `IndoorClimateLite.getTemperatureForSquare(square, player)` | the air at a square, in C, with the devices near it |
| `IndoorClimateLite.getRoomDescriptor(square)` | the zone and room the square is in (keys, kind, area, floor), or `nil` outdoors |
| `IndoorClimateLite.isIndoorSquare(square)` | `true` when the square has a room descriptor |
| `IndoorClimateLite.refreshConfig()` | reads the sandbox options again and returns `IndoorClimateLite.Config` |
| `IndoorClimateLite.VERSION` | the mod version, as in `mod.info` |
| `IndoorClimateLite.Config` | the sandbox options, read and clamped to their ranges, plus the fixed tuning values (`MaxElapsedHours` and others) |

`player` may be left out; it then means the first local player (there is none on a dedicated server). The exception
is `getTemperatureForPlayer()`, which returns the outdoor air without a player, as the original did.

## The sample

| Field | Meaning |
|---|---|
| `source` | always `"IndoorClimateLite"` |
| `version` | the mod version |
| `active` | `false` when the simulation is off; ignore the sample then |
| `airC` | the air the player feels: the room plus the devices near them |
| `baseRoomC` | the room's own temperature, without devices |
| `targetC` | the temperature the room is heading for |
| `outdoorC` | the outdoor air |
| `vanillaAirC` | the game's own air at the player, without this mod's heat sources |
| `indoors` | `true` in a simulated room |
| `powered` | grid power is on |
| `roomKey`, `buildingKey` | keys of the room and its zone (a map building or a player-built room) |
| `roomKind` | `"vanilla"` for a map room, `"player"` for a player-built room |
| `roomArea` | the room's floor area in squares |
| `leakScore` | how open the room's outer doors and windows are, 0 (sealed) to 1 |
| `openDoors`, `openWindows` | counts of open outer doors, and of open or broken windows and empty frames |
| `heaterActive`, `heaterCount` | whether, and how many, switched-on devices reach the player |
| `heaterDeltaC` | what those devices add to (or, for fans, take from) the air |
| `heaterRadius`, `heaterLeakRetention` | the largest reach among them, and the share of their effect the room's leaks leave |
| `envelopeComplete`, `cachedOpenings`, `thermalRoomCount`, `thermalEdgeCount`, `envelopeSquaresScanned`, `envelopeBuildingSquares` | figures from the building scan, for diagnostics |
| `hour` | the world age in hours (`getWorldAgeHours`) when the room was last stepped |

Outside the simulated rooms, the sample is the game's own air at the player with the devices near them applied:
`indoors` tells whether the square is in a room at all, and `roomKey` is `nil`.

## Where the numbers come from

- **On a dedicated server and in single player**, the API answers from the simulation itself. A server-side mod
  reads the same room air the player's client shows. `getTemperatureForSquare` knows every room with a saved
  temperature, as it was when last stepped (a room nobody is in is not stepped); an unvisited room gets the game's
  own air.
- **On a multiplayer client**, the API answers from the sample the server sent for that player. The client knows
  only the room its player is in: `getTemperatureForSquare` on any other square returns the game's own air there,
  with devices applied.

The settings and the Realistic Temperature check are read at most once a real second, so calling `isActive` or
`getTemperatureForPlayer` every frame is cheap.

## Example

```lua
local function roomAir(player)
    local icl = IndoorClimateLite
    if not icl or not icl.isActive() then
        return nil
    end
    local sample = icl.getTemperatureSample(player)
    if sample and sample.active ~= false and sample.indoors then
        return sample.airC
    end
    return nil
end
```
