-- Room simulation on a dedicated server: the player's own room, doors and windows a client opens with the vanilla
-- timed actions, a multi-storey building and its stairs, a building only partly in the loaded map, world data kept
-- across a restart, and what stepping many buildings costs.
if not isServer() then return end
require "PZE2E/PZE2E"

local Config = require("IndoorClimateRedone/Config")
local Places = require("IndoorClimateRedone/Game/Places")
local Envelope = require("IndoorClimateRedone/Envelope")
local Climate = require("IndoorClimateRedone/Climate")

local function hours()
    return getGameTime():getWorldAgeHours()
end

local function config()
    return Config.read(SandboxVars.IndoorClimateLite)
end

local function at(object)
    local sq = object:getSquare()
    return { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
end

-- Our own record of the runs on this world, to tell the first run from a restart.
local runs = 0
Events.OnInitGlobalModData.Add(function()
    local e2e = ModData.getOrCreate("IndoorClimateRedoneE2E")
    e2e.runs = (e2e.runs or 0) + 1
    runs = e2e.runs
end)

-- Map buildings with a loaded room square within `radius` tiles of the player: { { def, square, key } }, nearest
-- first.
local function buildingsNear(player, radius)
    local cell = getCell()
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local found, seen = {}, {}
    for r = 0, radius do
        for x = px - r, px + r do
            for y = py - r, py + r do
                if math.abs(x - px) == r or math.abs(y - py) == r then
                    local sq = cell:getGridSquare(x, y, 0)
                    local d = sq and Places.describe(sq) or nil
                    if d and d.buildingDef and not seen[d.key] then
                        seen[d.key] = true
                        found[#found + 1] = { def = d.buildingDef, square = sq, key = d.key }
                    end
                end
            end
        end
    end
    return found
end

PZE2E.test("the server simulates the player's room", {
    function(ctx)
        local sample = Climate.sample(ctx.player)
        if not sample then return "wait" end
        local d = Places.describe(ctx.player:getCurrentSquare())
        PZE2E.log("sample %s", PZE2E.describe(sample))
        PZE2E.check(d ~= nil and sample.buildingKey == d.key, "sample is for the player's zone %s",
            tostring(sample.buildingKey))
        PZE2E.check(sample.envelopeComplete == true, "the envelope scan finished")
        PZE2E.check((sample.cachedOpenings or 0) > 0, "%s openings found", tostring(sample.cachedOpenings))
        PZE2E.check(type(sample.airC) == "number", "room air %.2f C", sample.airC or -999)
        local e2e = ModData.getOrCreate("IndoorClimateRedoneE2E")
        if runs == 1 then
            e2e.houseKey = sample.buildingKey
            e2e.houseHour = sample.hour
        end
    end,
}, { startAfter = 3, every = 1 })

PZE2E.test("world data survives a restart", {
    function(ctx)
        local e2e = ModData.getOrCreate("IndoorClimateRedoneE2E")
        if runs < 2 then
            PZE2E.log("first run on this world (runs=%d): restart the server to check", runs)
            return
        end
        local data = Climate.data()
        local saved = data and e2e.houseKey and data.zones[e2e.houseKey] or nil
        PZE2E.check(data ~= nil and data.version == 1, "world data has version %s", tostring(data and data.version))
        PZE2E.check(saved ~= nil, "the house %s from the run before is in world data", tostring(e2e.houseKey))
        PZE2E.check(saved ~= nil and saved.roomStates ~= nil, "with its room states")
    end,
}, { startAfter = 1, every = 1 })

-- A room of the building on floor z and a free square in it, or nil.
local function roomOn(def, z)
    local rooms = def:getRooms()
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        if room:getZ() == z then
            local sq = room:getFreeSquare()
            if sq then return room, sq end
        end
    end
    return nil
end

-- Doors and windows opened by a client: the server sees the new state and the leaks follow. Only openings on the
-- player's floor, so the walk there needs no stairs.
local function findOpenable(player)
    local d = Places.describe(player:getCurrentSquare())
    local cache = d and Envelope.get(d.key) or nil
    if not cache or not cache.complete then return nil end
    local z = math.floor(player:getZ())
    local door, window
    for _, record in ipairs(cache.openings) do
        local o = record.object
        local here = o:getSquare() and o:getSquare():getZ() == z
        if here and not door and record.kind == "door" and instanceof(o, "IsoDoor") and not o:isLocked()
            and not o:isLockedByKey() and not o:IsOpen() then
            door = { object = o, exterior = true }
        end
        if here and not window and record.kind == "window" and instanceof(o, "IsoWindow") and not o:IsOpen()
            and not o:isSmashed() and not o:isLocked() and not o:isPermaLocked() then
            window = o
        end
    end
    if not door then
        for _, edge in pairs(cache.edgeMap) do
            for _, o in ipairs(edge.doors) do
                if not door and instanceof(o, "IsoDoor") and o:getSquare():getZ() == z and not o:IsOpen()
                    and not o:isLocked() and not o:isLockedByKey() then
                    door = { object = o, exterior = false, edgeKey = edge.key }
                end
            end
        end
    end
    return d, cache, door, window
end

PZE2E.test("doors and windows a player opens reach the simulation", {
    function(ctx)
        local d, cache, door, window = findOpenable(ctx.player)
        if not cache then return "wait" end
        -- A player who joins upstairs (where an earlier run left them) may find nothing to open there: go down.
        if not door and not window and d.buildingDef and ctx.player:getZ() >= 1 then
            if not ctx.state.movedDown then
                local _, sq = roomOn(d.buildingDef, 0)
                if sq then
                    ctx.state.movedDown = true
                    PZE2E.log("nothing to open on floor %d: moving to the ground floor", math.floor(ctx.player:getZ()))
                    PZE2E.ask(ctx.player, "icrTeleport", { x = sq:getX(), y = sq:getY(), z = 0 }, "down")
                end
            end
            if ctx.state.movedDown then return "wait" end
        end
        PZE2E.check(door ~= nil, "a closed, unlocked door on the player's floor")
        PZE2E.check(window ~= nil, "a closed, unlocked window in the outer wall on the player's floor")
        ctx.state.key, ctx.state.door, ctx.state.window = d.key, door, window
        ctx.state.before = Envelope.leaks(cache)
        if door then PZE2E.ask(ctx.player, "icrToggle", at(door.object), "door") end
    end,
    function(ctx)
        local s = ctx.state
        if s.door then
            if not ctx.answers.door then return "wait" end
            -- Give the queued actions (walk there, then open) a few game minutes.
            s.doorWaits = (s.doorWaits or 0) + 1
            if not s.door.object:IsOpen() and s.doorWaits < 6 then return "wait" end
            local cache = Envelope.get(s.key)
            PZE2E.check(s.door.object:IsOpen(), "the server sees the door the client opened (exterior=%s)",
                tostring(s.door.exterior))
            if s.door.exterior then
                PZE2E.check(Envelope.leaks(cache).openDoors > s.before.openDoors, "an open outer door counts as a leak")
            else
                local open = 0
                for _, edge in ipairs(Envelope.model(cache).edges) do
                    if edge.key == s.door.edgeKey then open = edge.openDoors end
                end
                PZE2E.check(open > 0, "the open inner door joins its rooms")
            end
            PZE2E.ask(ctx.player, "icrOpening", at(s.door.object), "doorSeen")
        end
        if s.window then PZE2E.ask(ctx.player, "icrToggle", at(s.window), "window") end
    end,
    function(ctx)
        local s = ctx.state
        if s.window then
            if not ctx.answers.window then return "wait" end
            s.windowWaits = (s.windowWaits or 0) + 1
            if not s.window:IsOpen() and s.windowWaits < 6 then return "wait" end
            local info = Envelope.leaks(Envelope.get(s.key))
            PZE2E.check(s.window:IsOpen(), "the server sees the window the client opened")
            PZE2E.check(info.openWindows > s.before.openWindows, "an open window counts as a leak (leak %.2f)",
                info.leakScore)
            PZE2E.ask(ctx.player, "icrOpening", at(s.window), "windowSeen")
        end
    end,
    function(ctx)
        local s = ctx.state
        if (s.door and not ctx.answers.doorSeen) or (s.window and not ctx.answers.windowSeen) then return "wait" end
        if s.door then
            PZE2E.check(ctx.answers.doorSeen.open == true, "the client sees the door open too")
            if s.door.object:IsOpen() then s.door.object:ToggleDoor(ctx.player) end
        end
        if s.window then
            PZE2E.check(ctx.answers.windowSeen.open == s.window:IsOpen(), "client and server agree on the window")
        end
    end,
}, { startAfter = 1, every = 1, maxWaits = 12 })

-- A building with rooms above the ground floor: every floor is scanned, and a player moving between floors
-- teaches the zone the stairs. The player is put back where they were at the end.

PZE2E.test("a multi-storey building and its stairs", {
    function(ctx)
        local start = ctx.player:getCurrentSquare()
        ctx.state.start = { x = start:getX(), y = start:getY(), z = start:getZ() }
        for _, b in ipairs(buildingsNear(ctx.player, 50)) do
            local _, low = roomOn(b.def, 0)
            local _, high = roomOn(b.def, 1)
            if low and high then
                ctx.state.key, ctx.state.low, ctx.state.high = b.key, low, high
                break
            end
        end
        if not PZE2E.check(ctx.state.key ~= nil, "a building with a first floor within 50 tiles") then return end
        PZE2E.log("building %s", ctx.state.key)
        local sq = ctx.state.low
        PZE2E.ask(ctx.player, "icrTeleport", { x = sq:getX(), y = sq:getY(), z = 0 }, "low")
    end,
    function(ctx)
        local s = ctx.state
        if not s.key then return end
        local sample = Climate.sample(ctx.player)
        local cache = Envelope.get(s.key)
        if not sample or sample.buildingKey ~= s.key or not cache or not cache.complete then return "wait" end
        local floors = {}
        for _, node in pairs(Envelope.model(cache).rooms) do floors[node.z] = true end
        PZE2E.check(floors[0] and floors[1], "the scan found rooms on the ground and first floor")
        s.lowRoom = sample.roomKey
        PZE2E.ask(ctx.player, "icrTeleport", { x = s.high:getX(), y = s.high:getY(), z = 1 }, "high")
    end,
    function(ctx)
        local s = ctx.state
        if not s.key then return end
        local sample = Climate.sample(ctx.player)
        if not sample or ctx.player:getZ() < 1 or sample.roomKey == s.lowRoom then return "wait" end
        local learned = false
        for _, edge in ipairs(Envelope.model(Envelope.get(s.key)).edges) do
            if edge.learned and (edge.a == s.lowRoom or edge.b == s.lowRoom) then learned = true end
        end
        PZE2E.check(sample.buildingKey == s.key, "upstairs is the same zone")
        PZE2E.check(learned, "the walk from %s to %s joined the two floors", tostring(s.lowRoom),
            tostring(sample.roomKey))
        PZE2E.ask(ctx.player, "icrTeleport", s.start, "back")
    end,
}, { startAfter = 1, every = 1, maxWaits = 15 })

PZE2E.test("a building only partly in the loaded map is retried", {
    function(ctx)
        local cell = getCell()
        local found
        for _, b in ipairs(buildingsNear(ctx.player, 110)) do
            local def = b.def
            local missing = 0
            for x = def:getX(), def:getX() + def:getW() - 1 do
                for y = def:getY(), def:getY() + def:getH() - 1 do
                    if not cell:getGridSquare(x, y, 0) then missing = missing + 1 end
                end
            end
            if missing > 0 then
                found = b
                break
            end
        end
        if not found then
            PZE2E.log("no building at the edge of the loaded map within 110 tiles; nothing to check")
            return
        end
        local d = Places.describe(found.square)
        local cache = Envelope.refresh(config(), d, hours(), 1000000)
        PZE2E.check(cache.complete and cache.partial, "%s: scan finished as partial", found.key)
        PZE2E.check(cache.missingSquares > 0, "%d squares were not loaded", cache.missingSquares)
    end,
}, { startAfter = 1, every = 1 })

PZE2E.test("cost of scanning and stepping the buildings near the player", {
    function(ctx)
        local list = buildingsNear(ctx.player, 50)
        local cfg = config()
        local now = hours()
        local squares, scanMs, maxScan = 0, 0, 0
        local count = math.min(#list, 40)
        for i = 1, count do
            local d = Places.describe(list[i].square)
            Envelope.clear()
            local t0 = getTimestampMs()
            local cache = Envelope.refresh(cfg, d, now, 1000000)
            local ms = getTimestampMs() - t0
            squares = squares + cache.squaresScanned
            scanMs = scanMs + ms
            maxScan = math.max(maxScan, ms)
            list[i].descriptor = d
        end
        -- Scans again, kept this time, then ten rounds of stepping every building.
        for i = 1, count do
            Envelope.refresh(cfg, list[i].descriptor, now, 1000000)
        end
        local t1 = getTimestampMs()
        for round = 1, 10 do
            for i = 1, count do
                Climate.stepSquare(list[i].square, now + round / 60)
            end
        end
        local stepMs = getTimestampMs() - t1
        PZE2E.log("%d buildings, %d squares: full scans %d ms in all (at most %d ms), %d zone steps %d ms (%.3f ms "
            .. "per step)", count, squares, scanMs, maxScan, count * 10, stepMs, stepMs / math.max(1, count * 10))
        PZE2E.check(count > 0, "buildings found near the player")
        PZE2E.check(stepMs / math.max(1, count * 10) < 2, "a zone step costs under 2 ms")
    end,
}, { startAfter = 1, every = 1 })
