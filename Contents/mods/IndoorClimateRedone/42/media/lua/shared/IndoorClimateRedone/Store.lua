-- World data: the saved state of every zone (map building or player-built room) and the grid power record.
--
-- The data is one plain table that the game saves with the world (global ModData under Store.KEY):
--   { version = 1, createdHour, zones = { [zone key] = <Rooms building or zone state> },
--     power = { on, offHour, lastSeenHour } }
-- A missing version means a world that never ran this mod. The game's own "new game" flag is not used: it can be
-- true for a world that is being loaded again.
--
-- Pure: the data table and the times are passed in.

local Store = {}

Store.KEY = "IndoorClimateRedone"
Store.VERSION = 1

-- Readies `data` for use. Returns "new" for a world without our data, "reset" when the data had a version this code
-- does not know (its zones are dropped), or "loaded".
function Store.open(data, nowHours)
    local status = "loaded"
    if data.version == nil then
        status = "new"
    elseif data.version ~= Store.VERSION then
        status = "reset"
    end
    if status ~= "loaded" then
        data.version = Store.VERSION
        data.createdHour = nowHours
        data.zones = {}
        data.power = {}
    end
    if type(data.zones) ~= "table" then
        data.zones = {}
    end
    if type(data.power) ~= "table" then
        data.power = {}
    end
    return status
end

-- The saved state of the descriptor's zone, or nil. A state saved under the room's own key (how the original
-- stored map rooms before it grouped them by building) is moved to the building's key.
function Store.zone(data, descriptor)
    local state = data.zones[descriptor.key]
    if type(state) == "table" then
        return state
    end
    local legacy = descriptor.legacyKey
    if legacy and legacy ~= descriptor.key and type(data.zones[legacy]) == "table" then
        state = data.zones[legacy]
        data.zones[descriptor.key] = state
        data.zones[legacy] = nil
        return state
    end
    return nil
end

function Store.put(data, key, state)
    data.zones[key] = state
end

-- Drops zone states beyond `maximum`, the least recently seen first, never one in `keep` (key -> true).
function Store.prune(data, maximum, keep)
    local records = {}
    for key, state in pairs(data.zones) do
        if not keep[key] then
            records[#records + 1] = { key = key, hour = type(state) == "table" and tonumber(state.lastSeenHour) or -1 }
        end
    end
    local excess = #records - maximum
    if excess <= 0 then
        return 0
    end
    table.sort(records, function(a, b)
        if a.hour ~= b.hour then
            return a.hour < b.hour
        end
        return a.key < b.key
    end)
    for index = 1, excess do
        data.zones[records[index].key] = nil
    end
    return excess
end

-- Records the grid power seen at `nowHours`: the hour it went off (kept until it comes back). Returns the record.
function Store.trackPower(data, powered, nowHours)
    local power = data.power
    if power.on == true and not powered then
        power.offHour = nowHours
    elseif power.on == false and powered then
        power.offHour = nil
    end
    power.on = powered == true
    power.lastSeenHour = nowHours
    return power
end

local NUMBER_FIELDS = { "temperature", "targetTemperature", "leakScore", "openDoors", "openWindows", "lastWorldHour",
    "lastSeenHour", "lastOutdoor", "lastVanillaAir", "area", "z", "roomModelVersion" }

local function copyState(source)
    local state = {}
    for _, name in ipairs(NUMBER_FIELDS) do
        state[name] = tonumber(source[name])
    end
    if type(source.lastPowered) == "boolean" then
        state.lastPowered = source.lastPowered
    end
    if type(source.kind) == "string" then
        state.kind = source.kind
    end
    return state
end

local function isMapKey(key)
    return type(key) == "string" and (key:sub(1, 9) == "building:" or key:sub(1, 8) == "vanilla:")
end

-- Takes over the map building states one player saved with the original mod (their player data's
-- IndoorClimateLite table) for every zone that has no state yet. Player-built room states are skipped: their keys
-- come from world region IDs, which differ between machines. Returns the number of zones taken over.
function Store.importOriginal(data, old)
    if type(old) ~= "table" or type(old.rooms) ~= "table" then
        return 0
    end
    local count = 0
    for key, source in pairs(old.rooms) do
        if isMapKey(key) and type(source) == "table" and data.zones[key] == nil and tonumber(source.temperature) then
            local state = copyState(source)
            if type(source.roomStates) == "table" then
                state.roomStates = {}
                for roomKey, room in pairs(source.roomStates) do
                    if isMapKey(roomKey) and type(room) == "table" and tonumber(room.temperature) then
                        state.roomStates[roomKey] = copyState(room)
                    end
                end
            end
            data.zones[key] = state
            count = count + 1
        end
    end
    return count
end

return Store
