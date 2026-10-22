-- The room simulation on the server (or in a single-player game): which zones players are in, scanning their
-- envelopes, stepping their room states and keeping each player's sample.
--
-- A zone is a map building or a player-built room (see Game/Places). Only zones with a player in them are scanned
-- and stepped. Every update (each game minute) advances the scans of occupied zones within the scan budgets and
-- steps each occupied zone every UpdateMinutes. A player who walks into another room or zone has that zone stepped
-- at once, as in the original. A zone nobody is in is not stepped; it catches up on the time it missed (up to
-- MaxElapsedHours) when someone comes back. A zone nobody has visited starts at outdoor air plus UnvisitedOffsetC.
--
-- Room states live in world data (Store), so all players see the same rooms and they survive a restart.
--
-- A sample's airC is the room's temperature changed by the switched-on devices near the player's square
-- (Heater.adjust); baseRoomC is the room's own. That part is worked out again whenever the player moves to another
-- square and whenever a device changes state, without stepping the room.
--
--   Climate.start(data, nowHours)   at world load, with the world data table (global ModData)
--   Climate.update(nowHours)        every game minute
--   Climate.watch(nowHours)         every tick: notices players changing rooms
--   Climate.stepSquare(square, h)   steps the zone of a square at once
--   Climate.reheat()                re-applies the devices to every sample (one was switched, say)
--   Climate.sample(player)          the player's room as last stepped, or nil outdoors
--   Climate.roomAt(square)          the saved temperature and leak score of the room a square is in

local Config = require("IndoorClimateRedone/Config")
local Leak = require("IndoorClimateRedone/Leak")
local Rooms = require("IndoorClimateRedone/Rooms")
local Store = require("IndoorClimateRedone/Store")
local Places = require("IndoorClimateRedone/Game/Places")
local Power = require("IndoorClimateRedone/Game/Power")
local Conflicts = require("IndoorClimateRedone/Game/Conflicts")
local HeatSources = require("IndoorClimateRedone/Game/HeatSources")
local Devices = require("IndoorClimateRedone/Game/Devices")
local Envelope = require("IndoorClimateRedone/Envelope")

local Climate = {}

Climate.LOG_PREFIX = "[IndoorClimateRedone] "

local data = nil
local config = Config.defaults()
-- player -> { square, inVehicle, descriptor, zoneKey, roomKey } (only square and inVehicle while outdoors)
local occupants = {}
-- player -> sample
local samples = {}
-- zone key -> { nextHour, lastHour }
local schedule = {}
-- online players whose original-mod data was looked at
local imported = {}
local updateCount = 0

-- Cost figures since the last report (Climate.report).
Climate.stats = nil

local function resetStats(nowHours)
    Climate.stats = { since = nowHours, updates = 0, zoneSteps = 0, squaresScanned = 0, ms = 0, maxMs = 0,
        occupiedMax = 0 }
end

local function log(message)
    print(Climate.LOG_PREFIX .. tostring(message))
end

local function debugLog(message)
    if config.DebugLogging then
        log(message)
    end
end

local function now()
    return getTimestampMs()
end

-- True while the simulation runs: enabled in the sandbox options, and no conflicting mod (Game/Conflicts).
function Climate.active()
    return config.Enabled == true and not Conflicts.active()
end

-- The players whose rooms are simulated here: online players on a server, the local players otherwise.
function Climate.players()
    local list = {}
    if isServer() then
        local online = getOnlinePlayers()
        for index = 0, online:size() - 1 do
            list[#list + 1] = online:get(index)
        end
    else
        for index = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(index)
            if player then
                list[#list + 1] = player
            end
        end
    end
    return list
end

function Climate.start(worldData, nowHours)
    data = worldData
    config = Config.read(SandboxVars and SandboxVars.IndoorClimateLite)
    local status = Store.open(data, nowHours)
    if status == "reset" then
        log("world data had an unknown version; room states start over")
    end
    occupants, samples, schedule, imported = {}, {}, {}, {}
    Envelope.clear()
    resetStats(nowHours)
    log("started (" .. status .. " world data)")
end

local function ensureStarted(nowHours)
    if not data then
        Climate.start(ModData.getOrCreate(Store.KEY), nowHours)
    end
end

-- Where the player is now, or nil when they are outdoors, in a vehicle or dead.
local function locate(player)
    if player:isDead() or player:getVehicle() then
        return nil
    end
    local square = player:getCurrentSquare()
    local descriptor = Places.describe(square)
    if not descriptor then
        return nil
    end
    return { square = square, descriptor = descriptor, zoneKey = descriptor.key, roomKey = Places.roomKey(descriptor) }
end

-- zone key -> { descriptor, square, members = { { player, where } } }, and the zone keys in a fixed order.
local function occupiedZones(players)
    local zones, order = {}, {}
    for _, player in ipairs(players) do
        local where = occupants[player]
        if where and where.zoneKey then
            local zone = zones[where.zoneKey]
            if not zone then
                zone = { key = where.zoneKey, descriptor = where.descriptor, square = where.square, members = {} }
                zones[where.zoneKey] = zone
                order[#order + 1] = where.zoneKey
            end
            zone.members[#zone.members + 1] = { player = player, where = where }
        end
    end
    table.sort(order)
    return zones, order
end

local function readAir(square)
    local climate = getClimateManager()
    local outdoorC = tonumber(climate:getTemperature()) or 15.0
    local vanillaAirC = square and tonumber(climate:getAirTemperatureForSquare(square)) or outdoorC
    return outdoorC, vanillaAirC
end

-- The outdoor air and the game's air at `square`, without the mod's own heat sources (in single player the client's
-- bridge source shares the cell; counting it would let a room warm itself).
local function readClimate(square)
    return HeatSources.without(readAir, square)
end

-- Sets the sample's airC and heater fields from its baseRoomC and the devices near `square`.
local function applyDevices(sample, square)
    local airC, delta, count, radius, retention = Devices.adjust(square, sample.baseRoomC, sample.leakScore, config)
    sample.airC = airC
    sample.heaterActive = count > 0
    sample.heaterCount = count
    sample.heaterDeltaC = delta
    sample.heaterRadius = radius
    sample.heaterLeakRetention = retention
    return sample
end

local function makeSample(member, room, zone, info, w)
    local _, vanillaAirC = readClimate(member.where.square)
    local descriptor = member.where.descriptor
    return applyDevices({
        airC = room.temperature,
        baseRoomC = room.temperature,
        targetC = room.targetTemperature,
        outdoorC = w.outdoorC,
        vanillaAirC = vanillaAirC,
        indoors = true,
        powered = w.powered,
        roomKey = member.where.roomKey,
        buildingKey = zone.key,
        roomKind = descriptor.kind,
        roomArea = room.area or descriptor.area,
        leakScore = room.leakScore,
        openDoors = room.openDoors,
        openWindows = room.openWindows,
        envelopeComplete = info and info.complete or nil,
        cachedOpenings = info and info.openingCount or nil,
        envelopeSquaresScanned = info and info.squaresScanned or nil,
        envelopeBuildingSquares = info and info.buildingSquaresSeen or nil,
        thermalRoomCount = info and info.roomCount or nil,
        thermalEdgeCount = info and info.edgeCount or nil,
        hour = w.nowHours,
    }, member.where.square)
end

-- The player's sample with the devices applied for where they stand now: a new table, so the sender sees a change.
local function reheatPlayer(player)
    local sample, where = samples[player], occupants[player]
    if not sample or not where or not where.square then
        return
    end
    local copy = {}
    for name, value in pairs(sample) do
        copy[name] = value
    end
    samples[player] = applyDevices(copy, where.square)
end

local function logStep(sample, info)
    debugLog(string.format(
        "building=%s room=%s air=%.2f target=%.2f vanilla=%.2f outdoor=%.2f power=%s leak=%.2f doors=%d windows=%d "
            .. "envelope=%s openings=%s rooms=%s edges=%s scanned=%s inside=%s",
        sample.buildingKey, sample.roomKey, sample.airC, sample.targetC or 0, sample.vanillaAirC, sample.outdoorC,
        sample.powered and "on" or "off", sample.leakScore or 0, sample.openDoors or 0, sample.openWindows or 0,
        info and (info.complete and (info.partial and "partial" or "ready") or "building") or "local",
        info and tostring(info.openingCount) or "-", info and tostring(info.roomCount) or "-",
        info and tostring(info.edgeCount) or "-", info and tostring(info.squaresScanned) or "-",
        info and tostring(info.buildingSquaresSeen) or "-"))
end

-- Steps one occupied zone to `nowHours` and refreshes its members' samples.
local function stepZone(zone, nowHours, power)
    local descriptor = zone.descriptor
    local outdoorC, vanillaAirC = readClimate(zone.square)
    local w = { kind = descriptor.kind, area = descriptor.area, powered = power.on, nowHours = nowHours,
        outdoorC = outdoorC, vanillaAirC = vanillaAirC, powerOffHour = power.offHour }

    local state = Store.zone(data, descriptor)
    if not state then
        state = Rooms.newBuilding(config, outdoorC, nowHours, power.on)
        Store.put(data, zone.key, state)
    end

    local info = nil
    local cache = Envelope.refresh(config, descriptor, nowHours, 0)
    if cache then
        info = Envelope.leaks(cache)
        if not info.complete then
            -- Until the scan is done, what is near each player counts too.
            for _, member in ipairs(zone.members) do
                Leak.mergeNearby(info, member.where.roomKey, Envelope.nearby(config, member.where.square, zone.key))
            end
        end
    end

    if descriptor.kind == "vanilla" and cache then
        local model = Envelope.model(cache)
        w.rooms, w.edges, w.leaks = model.rooms, model.edges, info
        -- The zone's own room (the first player's) drives the step; other players' rooms that the scan does not
        -- know yet are added with a zero-hour step.
        w.roomKey = Places.roomKey(descriptor)
        Rooms.advanceBuilding(config, state, w)
        for _, member in ipairs(zone.members) do
            if not state.roomStates[member.where.roomKey] then
                w.roomKey = member.where.roomKey
                Rooms.advanceBuilding(config, state, w)
            end
        end
        for _, member in ipairs(zone.members) do
            local sample = makeSample(member, state.roomStates[member.where.roomKey], zone, info, w)
            samples[member.player] = sample
            logStep(sample, info)
        end
    else
        if info then
            w.leaks = Leak.forRoom(info, descriptor.roomKey)
        else
            w.leaks = Envelope.nearby(config, zone.square, zone.key)
        end
        Rooms.advanceZone(config, state, w)
        for _, member in ipairs(zone.members) do
            local sample = makeSample(member, state, zone, info, w)
            samples[member.player] = sample
            logStep(sample, info)
        end
    end

    local entry = schedule[zone.key] or {}
    entry.lastHour = nowHours
    entry.nextHour = nowHours + config.UpdateMinutes / 60.0
    schedule[zone.key] = entry
    Climate.stats.zoneSteps = Climate.stats.zoneSteps + 1
end

local function isDue(key, nowHours)
    local entry = schedule[key]
    if not entry or not entry.nextHour then
        return true
    end
    local interval = config.UpdateMinutes / 60.0
    if nowHours < entry.lastHour - 0.001 or entry.nextHour > nowHours + interval then
        -- The clock went back, or the interval got shorter.
        return true
    end
    return nowHours >= entry.nextHour
end

local function importOriginal(player)
    if imported[player] then
        return
    end
    imported[player] = true
    local count = Store.importOriginal(data, player:getModData().IndoorClimateLite)
    if count > 0 then
        log("took over " .. count .. " building states that " .. tostring(player:getUsername())
            .. " saved with Indoor Climate")
    end
end

local function clearAll()
    occupants, samples = {}, {}
end

local function learnTransition(before, after)
    if before and after and before.descriptor.kind == "vanilla" and after.descriptor.kind == "vanilla"
        and before.zoneKey == after.zoneKey and tonumber(before.descriptor.z) ~= tonumber(after.descriptor.z) then
        Envelope.learnTransition(after.zoneKey, before.roomKey, after.roomKey)
    end
end

-- Re-reads every player's location. Returns the set of zone keys whose occupants changed room or zone.
local function relocate(players)
    local changed = {}
    local online = {}
    for _, player in ipairs(players) do
        online[player] = true
        local before = occupants[player]
        if not before then
            importOriginal(player)
        end
        local square = player:getCurrentSquare()
        local inVehicle = player:getVehicle() ~= nil
        if not before or before.square ~= square or before.inVehicle ~= inVehicle then
            local after = locate(player)
            if after then
                after.inVehicle = inVehicle
            end
            if not after then
                samples[player] = nil
                occupants[player] = { square = square, inVehicle = inVehicle }
            else
                local beforeRoom = before and before.zoneKey and before or nil
                occupants[player] = after
                if not beforeRoom or beforeRoom.zoneKey ~= after.zoneKey or beforeRoom.roomKey ~= after.roomKey then
                    learnTransition(beforeRoom, after)
                    changed[after.zoneKey] = true
                else
                    reheatPlayer(player)
                end
            end
        end
    end
    for player in pairs(occupants) do
        if not online[player] then
            occupants[player] = nil
            samples[player] = nil
            imported[player] = nil
        end
    end
    return changed
end

-- Every game minute: scan and step occupied zones.
function Climate.update(nowHours)
    ensureStarted(nowHours)
    config = Config.read(SandboxVars and SandboxVars.IndoorClimateLite)
    if not Climate.active() then
        clearAll()
        return
    end
    local started = now()
    updateCount = updateCount + 1
    local power = Store.trackPower(data, Power.grid(), nowHours)
    local players = Climate.players()
    local changed = relocate(players)
    local zones, order = occupiedZones(players)

    -- Scans share the server budget; the zone that goes first rotates so none waits for ever.
    local remaining = config.ServerScanBudget
    local count = #order
    for offset = 0, count - 1 do
        local zone = zones[order[(updateCount + offset) % count + 1]]
        local budget = math.min(config.EnvelopeScanBudget, remaining)
        local _, visited = Envelope.refresh(config, zone.descriptor, nowHours, budget)
        remaining = remaining - (visited or 0)
        Climate.stats.squaresScanned = Climate.stats.squaresScanned + (visited or 0)
    end

    local keep = {}
    for _, key in ipairs(order) do
        keep[key] = true
        if changed[key] or isDue(key, nowHours) then
            stepZone(zones[key], nowHours, power)
        end
    end
    Envelope.prune(config.MaxEnvelopeCaches, keep)
    Store.prune(data, config.MaxStoredZones, keep)
    for key in pairs(schedule) do
        if not keep[key] then
            schedule[key] = nil
        end
    end

    local stats = Climate.stats
    local ms = now() - started
    stats.updates = stats.updates + 1
    stats.ms = stats.ms + ms
    stats.maxMs = math.max(stats.maxMs, ms)
    stats.occupiedMax = math.max(stats.occupiedMax, count)
    if config.DebugLogging and nowHours - stats.since >= 1.0 then
        Climate.report(nowHours)
    end
end

-- Logs the cost figures since the last report and starts new ones.
function Climate.report(nowHours)
    local stats = Climate.stats
    log(string.format("cost over %.1f h: %d updates, %d zone steps, %d squares scanned, %d ms in all, at most %d ms "
        .. "in one update, at most %d zones occupied", nowHours - stats.since, stats.updates, stats.zoneSteps,
        stats.squaresScanned, stats.ms, stats.maxMs, stats.occupiedMax))
    resetStats(nowHours)
end

-- Every tick: a player who changed room or zone has that zone stepped at once.
function Climate.watch(nowHours)
    if not data or not Climate.active() then
        return
    end
    local players = Climate.players()
    local changed = relocate(players)
    local any = false
    for _ in pairs(changed) do
        any = true
    end
    if not any then
        return
    end
    local power = Store.trackPower(data, Power.grid(), nowHours)
    local zones, order = occupiedZones(players)
    -- A zone just entered gets a head start on its scan, within the server budget for this tick.
    local remaining = config.ServerScanBudget
    for _, key in ipairs(order) do
        if changed[key] then
            local zone = zones[key]
            local budget = math.min(config.EnvelopeScanBudget, remaining)
            local _, visited = Envelope.refresh(config, zone.descriptor, nowHours, budget)
            remaining = remaining - (visited or 0)
            Climate.stats.squaresScanned = Climate.stats.squaresScanned + (visited or 0)
            stepZone(zone, nowHours, power)
        end
    end
end

-- Steps the zone `square` is in right now (a device there was switched, say), with the players who are in it.
-- Returns false when the square is outdoors or the simulation is off.
function Climate.stepSquare(square, nowHours)
    if not data or not Climate.active() then
        return false
    end
    local descriptor = Places.describe(square)
    if not descriptor then
        return false
    end
    local zones = occupiedZones(Climate.players())
    local zone = zones[descriptor.key]
        or { key = descriptor.key, descriptor = descriptor, square = square, members = {} }
    stepZone(zone, nowHours, Store.trackPower(data, Power.grid(), nowHours))
    return true
end

function Climate.reheat()
    for player in pairs(samples) do
        reheatPlayer(player)
    end
end

-- The player's room as last stepped (a plain table), or nil when they are not in a simulated room.
function Climate.sample(player)
    return samples[player]
end

-- The saved temperature and leak score of the room `square` is in, or nil when it has no state yet (a zone nobody
-- visited) or the square is outdoors. Read only: unlike stepping, it does not move a state saved under an older key.
function Climate.roomAt(square)
    if not data then
        return nil
    end
    local descriptor = Places.describe(square)
    if not descriptor then
        return nil
    end
    local state = data.zones[descriptor.key]
    if type(state) ~= "table" and descriptor.legacyKey then
        state = data.zones[descriptor.legacyKey]
    end
    if type(state) ~= "table" then
        return nil
    end
    local room = type(state.roomStates) == "table" and state.roomStates[Places.roomKey(descriptor)] or nil
    if type(room) == "table" and tonumber(room.temperature) then
        return tonumber(room.temperature), tonumber(room.leakScore) or tonumber(state.leakScore) or 0
    end
    if tonumber(state.temperature) then
        return tonumber(state.temperature), tonumber(state.leakScore) or 0
    end
    return nil
end

-- The world data table (for tests and diagnostics).
function Climate.data()
    return data
end

-- The settings of the last update.
function Climate.config()
    return config
end

return Climate
