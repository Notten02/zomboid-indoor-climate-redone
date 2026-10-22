-- Room states: stepping every room of a building to the current hour, and the keys rooms are stored under.
--
-- A building state is a plain table that is saved as is:
--   { temperature, targetTemperature, leakScore, openDoors, openWindows,     -- of the room last looked at
--     lastWorldHour, lastSeenHour, lastPowered, lastOutdoor, lastVanillaAir,
--     kind, area, roomModelVersion,
--     roomStates = { [roomKey] = <room state> } }
-- A room state has the same fields (minus kind and roomStates) plus `area` and `z`. The keys and field names are the
-- original mod's, so its saved rooms can be read.
--
-- Pure: the scan results, power, temperatures and times are passed in.

local Config = require("IndoorClimateRedone/Config")
local Model = require("IndoorClimateRedone/Model")
local Leak = require("IndoorClimateRedone/Leak")

local clamp = Config.clamp

local Rooms = {}

Rooms.ROOM_MODEL_VERSION = 1

-- Keys. A map building is keyed by its bounds, a map room by its RoomDef ID, a player-built room by its world
-- region ID and floor.
function Rooms.buildingKey(x, y, w, h)
    return string.format("building:x%d:y%d:w%d:h%d", x, y, w, h)
end

function Rooms.buildingIdKey(id)
    return "building:" .. tostring(id)
end

function Rooms.vanillaRoomKey(id)
    return "vanilla:" .. tostring(id)
end

function Rooms.playerRoomKey(regionId, z)
    return "player:region:" .. tostring(regionId) .. ":z" .. tostring(z)
end

-- The state of a building nobody has visited yet: outdoor air plus UnvisitedOffsetC, no leaks.
function Rooms.newBuilding(config, outdoorC, nowHours, powered)
    return {
        temperature = Model.initial(config, outdoorC),
        lastWorldHour = nowHours,
        lastSeenHour = nowHours,
        lastPowered = powered,
        leakScore = 0,
        openDoors = 0,
        openWindows = 0,
    }
end

-- One room's temperature stepped from its lastWorldHour to `nowHours` (at most MaxElapsedHours).
--
-- When the room was last stepped with power and the power went off in between (`powerOffHour`, the hour the grid
-- went down, or nil), the time before the cut is stepped powered, with the vanilla air of the last update, and the
-- time after unpowered. The room's current leakScore applies to the whole stretch.
function Rooms.stepRoom(config, state, powered, nowHours, outdoorC, vanillaAirC, powerOffHour)
    local hours, lastHour = Model.elapsed(config, state.lastWorldHour, nowHours)
    local current = tonumber(state.temperature) or vanillaAirC
    local leakScore = clamp(state.leakScore or 0, 0, 1)
    local offHour = tonumber(powerOffHour)

    if state.lastPowered == true and not powered and offHour and offHour > lastHour and offHour < nowHours then
        local previousVanilla = tonumber(state.lastVanillaAir) or config.PoweredTargetC
        current = Model.step(config, current, offHour - lastHour, true, outdoorC, previousVanilla, leakScore)
        return Model.step(config, current, nowHours - offHour, false, outdoorC, vanillaAirC, leakScore)
    end
    return Model.step(config, current, hours, powered, outdoorC, vanillaAirC, leakScore)
end

-- The state of one room in a building, created on first use from the building's own values. `node` (from the scan:
-- { area, z }) updates the room's floor area.
function Rooms.ensureRoom(building, roomKey, node, nowHours, powered, vanillaAirC)
    building.roomStates = building.roomStates or {}
    local room = building.roomStates[roomKey]
    if type(room) ~= "table" then
        room = {
            temperature = tonumber(building.temperature) or vanillaAirC,
            lastWorldHour = tonumber(building.lastWorldHour) or nowHours,
            lastSeenHour = tonumber(building.lastSeenHour) or nowHours,
            lastPowered = building.lastPowered,
            lastVanillaAir = tonumber(building.lastVanillaAir) or vanillaAirC,
            leakScore = 0,
            openDoors = 0,
            openWindows = 0,
        }
        if room.lastPowered == nil then
            room.lastPowered = powered
        end
        building.roomStates[roomKey] = room
    end
    if node then
        room.area = math.max(1, tonumber(node.area) or 1)
        room.z = tonumber(node.z) or room.z
    else
        room.area = math.max(1, tonumber(room.area) or 1)
    end
    return room
end

local function finishStep(config, state, w, temperature)
    state.temperature = temperature
    state.lastWorldHour = w.nowHours
    state.lastSeenHour = w.nowHours
    state.lastPowered = w.powered
    state.lastOutdoor = w.outdoorC
    state.lastVanillaAir = w.vanillaAirC
    state.targetTemperature = Model.target(config, w.powered, w.outdoorC, state.leakScore)
end

local function setLeaks(state, leaks)
    state.leakScore = clamp(leaks and leaks.leakScore or 0, 0, 1)
    state.openDoors = leaks and leaks.openDoors or 0
    state.openWindows = leaks and leaks.openWindows or 0
end

-- Steps a map building to `w.nowHours` and returns the state of the room `w.roomKey`. `w` is what the update saw:
--   roomKey       the room being looked at (it is always stepped)
--   kind, area    the building's kind ("vanilla") and floor area
--   rooms         { [roomKey] = { area, z } } from the envelope scan, may be empty
--   edges         { { a = roomKey, b = roomKey, <Leak.edgeRate counts> }, ... } in a fixed order
--   leaks         Leak.summarize result (may be nil): each room's leak score
--   powered, nowHours, outdoorC, vanillaAirC, powerOffHour
--
-- Every room known to the scan or the leaks is stepped on its own, then each pair of joined rooms shares heat for
-- the time since the building's last update. The looked-at room's values are copied onto the building.
function Rooms.advanceBuilding(config, building, w)
    local rooms = w.rooms or {}
    local leaks = w.leaks or Leak.summarize({})
    local current = Leak.forRoom(leaks, w.roomKey)

    local active = {}
    for key in pairs(rooms) do
        active[key] = true
    end
    for key in pairs(leaks.perRoom) do
        active[key] = true
    end
    active[w.roomKey] = true

    local hours = Model.elapsed(config, building.lastWorldHour, w.nowHours)

    for key in pairs(active) do
        local room = Rooms.ensureRoom(building, key, rooms[key], w.nowHours, w.powered, w.vanillaAirC)
        setLeaks(room, key == w.roomKey and current or leaks.perRoom[key])
        finishStep(config, room,
            w, Rooms.stepRoom(config, room, w.powered, w.nowHours, w.outdoorC, w.vanillaAirC, w.powerOffHour))
    end

    if hours > 0 then
        for _, edge in ipairs(w.edges or {}) do
            local a = building.roomStates[edge.a]
            local b = building.roomStates[edge.b]
            local rate = Leak.edgeRate(edge)
            if a and b and rate > 0 then
                a.temperature, b.temperature = Model.exchange(a.temperature, b.temperature, a.area, b.area, hours, rate)
            end
        end
    end

    local selected = building.roomStates[w.roomKey]
    building.temperature = selected.temperature
    building.leakScore = selected.leakScore
    building.openDoors = selected.openDoors
    building.openWindows = selected.openWindows
    building.targetTemperature = selected.targetTemperature
    building.lastWorldHour = w.nowHours
    building.lastSeenHour = w.nowHours
    building.lastPowered = w.powered
    building.lastOutdoor = w.outdoorC
    building.lastVanillaAir = w.vanillaAirC
    building.kind = w.kind
    building.area = w.area
    building.roomModelVersion = Rooms.ROOM_MODEL_VERSION
    return selected
end

-- Steps a space that is one room (a player-built room, or a map room outside any building) to `w.nowHours`, with
-- `w.leaks` ({ leakScore, openDoors, openWindows }) and the other fields as for advanceBuilding. Returns `state`.
function Rooms.advanceZone(config, state, w)
    setLeaks(state, w.leaks)
    finishStep(config, state,
        w, Rooms.stepRoom(config, state, w.powered, w.nowHours, w.outdoorC, w.vanillaAirC, w.powerOffHour))
    state.kind = w.kind
    state.area = w.area
    return state
end

return Rooms
