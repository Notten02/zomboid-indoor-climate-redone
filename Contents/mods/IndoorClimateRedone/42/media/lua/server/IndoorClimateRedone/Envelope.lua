-- Building envelopes: the rooms of a zone, how they join, and the doors and windows in its outer wall.
--
-- A map building is scanned square by square over its BuildingDef bounds, a player-built room by flooding out from
-- the square it was entered from. A scan runs in chunks of a few hundred squares per update, so a large building is
-- finished over several updates. The rules are the original mod's (ICL_BuildingEnvelope), with three differences:
--   - one scan per zone for the whole server instead of one per client;
--   - squares are only read where the map is loaded (near a player). A square whose ground floor is not loaded is
--     counted as missing, and a scan with missing squares is redone after EnvelopeRetryHours instead of 6 hours;
--   - no object events. The game does not report changes made on the server, so the state of every known opening
--     and inner door is read again on each update. A known object that left its square makes the next update
--     rescan the zone, and every finished scan is redone after EnvelopeRefreshHours.
--
-- Game adapter. What it hands to the model is plain: Leak opening tables and edge counts (see Leak and Rooms).

local Leak = require("IndoorClimateRedone/Leak")
local Places = require("IndoorClimateRedone/Game/Places")
local Openings = require("IndoorClimateRedone/Game/Openings")

local Envelope = {}

-- zone key -> scan cache
local caches = {}

local function listSize(list)
    return list and tonumber(list:size()) or 0
end

local function sameZone(square, key)
    local descriptor = Places.describe(square)
    return descriptor ~= nil and descriptor.key == key, descriptor
end

-- The floors to scan: those the building's rooms are on, plus the floor it was entered on. A building whose
-- BuildingDef lists no rooms is searched a few floors around that floor (the original's fallback).
local function zLevels(descriptor)
    local levels, seen = {}, {}
    local rooms = descriptor.buildingDef:getRooms()
    for index = 0, listSize(rooms) - 1 do
        local roomDef = rooms:get(index)
        local z = roomDef and tonumber(roomDef:getZ()) or nil
        if z and not seen[z] then
            seen[z] = true
            levels[#levels + 1] = z
        end
    end
    local currentZ = tonumber(descriptor.z) or 0
    if not seen[currentZ] then
        seen[currentZ] = true
        levels[#levels + 1] = currentZ
    end
    if #levels == 1 and listSize(rooms) == 0 then
        local minimumZ, maximumZ = math.min(0, currentZ), math.max(7, currentZ)
        local chunk = descriptor.anchorSquare and descriptor.anchorSquare:getChunk() or nil
        if chunk then
            minimumZ = tonumber(chunk:getMinLevel()) or minimumZ
            maximumZ = tonumber(chunk:getMaxLevel()) or maximumZ
        end
        for z = math.max(minimumZ, currentZ - 4), math.min(maximumZ, currentZ + 8) do
            if not seen[z] then
                seen[z] = true
                levels[#levels + 1] = z
            end
        end
    end
    table.sort(levels)
    return levels
end

local function resetScan(cache, descriptor, nowHours)
    cache.kind = descriptor.kind
    cache.openings = {}
    cache.seenObjects = {}
    cache.seenSquares = {}
    cache.roomNodes = {}
    cache.edgeMap = {}
    cache.learnedEdges = cache.learnedEdges or {}
    cache.complete = false
    cache.dirty = false
    cache.startedHour = nowHours
    cache.builtHour = nil
    cache.squaresScanned = 0
    cache.buildingSquaresSeen = 0
    cache.missingSquares = 0
    cache.anchorSquare = descriptor.anchorSquare
    if descriptor.kind == "player" then
        cache.scanMode = "player"
        cache.expectedSquares = math.max(1, tonumber(descriptor.area) or 1)
        cache.queue = { descriptor.anchorSquare }
        cache.queueIndex = 1
        cache.queuedSquares = {}
        if descriptor.anchorSquare then
            cache.queuedSquares[descriptor.anchorSquare] = true
        end
        return
    end
    cache.scanMode = "building"
    cache.minX = tonumber(descriptor.buildingX)
    cache.minY = tonumber(descriptor.buildingY)
    cache.width = math.max(0, tonumber(descriptor.buildingW) or 0)
    cache.height = math.max(0, tonumber(descriptor.buildingH) or 0)
    cache.zLevels = zLevels(descriptor)
    cache.zIndex = 1
    cache.xOffset = 0
    cache.yOffset = 0
end

local function addOpening(cache, object)
    if not object or cache.seenObjects[object] then
        return
    end
    cache.seenObjects[object] = true
    local kind = Openings.kind(object)
    if kind and Openings.isExterior(object, cache.key) then
        cache.openings[#cache.openings + 1] = {
            object = object,
            kind = kind,
            roomKey = Openings.interiorRoomKey(object, cache.key),
        }
    end
end

local function scanSquareObjects(cache, square)
    if not square or cache.seenSquares[square] then
        return
    end
    cache.seenSquares[square] = true
    Openings.visit(square, function(object) addOpening(cache, object) end)
end

local function scanExteriorNeighbor(cache, square)
    if square and not sameZone(square, cache.key) then
        scanSquareObjects(cache, square)
    end
end

local function pairKey(a, b)
    if a < b then
        return a .. "|" .. b, a, b
    end
    return b .. "|" .. a, b, a
end

local function getOrCreateEdge(cache, roomA, roomB)
    local key, first, second = pairKey(roomA, roomB)
    local edge = cache.edgeMap[key]
    if not edge then
        edge = { key = key, a = first, b = second, doors = {}, doorSet = {}, passages = 0, walls = 0 }
        cache.edgeMap[key] = edge
    end
    return edge
end

local function recordRoomConnection(cache, roomKey, square, neighbor)
    if not neighbor then
        return
    end
    local inZone, descriptor = sameZone(neighbor, cache.key)
    if not inZone then
        return
    end
    local neighborRoomKey = Places.roomKey(descriptor)
    if not neighborRoomKey or neighborRoomKey == roomKey then
        return
    end
    local edge = getOrCreateEdge(cache, roomKey, neighborRoomKey)
    local door = Openings.doorBetween(square, neighbor)
    if door then
        if not edge.doorSet[door] then
            edge.doorSet[door] = true
            edge.doors[#edge.doors + 1] = door
        end
        return
    end
    if square:isBlockedTo(neighbor) == true then
        edge.walls = edge.walls + 1
    else
        edge.passages = edge.passages + 1
    end
end

local function scanRoomSquare(cache, square, descriptor)
    local roomKey = Places.roomKey(descriptor)
    if roomKey then
        local node = cache.roomNodes[roomKey]
        if not node then
            node = { area = 0, z = tonumber(square:getZ()) or tonumber(descriptor.z) or 0 }
            cache.roomNodes[roomKey] = node
        end
        node.area = node.area + 1
        recordRoomConnection(cache, roomKey, square, square:getE())
        recordRoomConnection(cache, roomKey, square, square:getS())
    end
    scanSquareObjects(cache, square)
    scanExteriorNeighbor(cache, square:getN())
    scanExteriorNeighbor(cache, square:getS())
    scanExteriorNeighbor(cache, square:getW())
    scanExteriorNeighbor(cache, square:getE())
end

local function finishScan(cache, nowHours)
    if cache.buildingSquaresSeen <= 0 then
        -- Nothing of the zone was found (not loaded yet): start over on the next update.
        if cache.scanMode == "player" then
            cache.queue = { cache.anchorSquare }
            cache.queueIndex = 1
            cache.queuedSquares = {}
            if cache.anchorSquare then
                cache.queuedSquares[cache.anchorSquare] = true
            end
        else
            cache.zIndex = 1
            cache.xOffset = 0
            cache.yOffset = 0
        end
        cache.squaresScanned = 0
        cache.missingSquares = 0
        return
    end
    cache.complete = true
    cache.partial = cache.missingSquares > 0
    cache.builtHour = nowHours
    cache.zLevels = nil
    cache.seenObjects = nil
    cache.seenSquares = nil
    cache.queue = nil
    cache.queueIndex = nil
    cache.queuedSquares = nil
    for _, edge in pairs(cache.edgeMap) do
        edge.doorSet = nil
    end
end

local function enqueuePlayerNeighbor(cache, square)
    if not square or cache.queuedSquares[square] or not sameZone(square, cache.key) then
        return
    end
    cache.queuedSquares[square] = true
    cache.queue[#cache.queue + 1] = square
end

-- Returns the number of squares visited.
local function advancePlayerScan(cache, nowHours, budget)
    local processed = 0
    while processed < budget do
        local square = cache.queue[cache.queueIndex]
        if not square then
            finishScan(cache, nowHours)
            return processed
        end
        cache.queueIndex = cache.queueIndex + 1
        cache.squaresScanned = cache.squaresScanned + 1
        processed = processed + 1
        local inZone, descriptor = sameZone(square, cache.key)
        if inZone then
            cache.buildingSquaresSeen = cache.buildingSquaresSeen + 1
            scanRoomSquare(cache, square, descriptor)
            enqueuePlayerNeighbor(cache, square:getN())
            enqueuePlayerNeighbor(cache, square:getS())
            enqueuePlayerNeighbor(cache, square:getW())
            enqueuePlayerNeighbor(cache, square:getE())
        end
    end
    return processed
end

-- Returns the number of squares visited.
local function advanceBuildingScan(cache, nowHours, budget)
    local cell = getCell()
    if not cell or not cache.minX or not cache.minY or cache.width <= 0 or cache.height <= 0 then
        return 0
    end
    local processed = 0
    while processed < budget do
        local z = cache.zLevels[cache.zIndex]
        if z == nil then
            finishScan(cache, nowHours)
            return processed
        end
        local x = cache.minX + cache.xOffset
        local y = cache.minY + cache.yOffset
        local square = cell:getGridSquare(x, y, z)
        cache.squaresScanned = cache.squaresScanned + 1
        processed = processed + 1
        if square then
            local inZone, descriptor = sameZone(square, cache.key)
            if inZone then
                cache.buildingSquaresSeen = cache.buildingSquaresSeen + 1
                scanRoomSquare(cache, square, descriptor)
            end
        elseif z == 0 or not cell:getGridSquare(x, y, 0) then
            -- Upper floors have squares only where something was built; a missing ground floor means the map
            -- is not loaded there.
            cache.missingSquares = cache.missingSquares + 1
        end
        cache.yOffset = cache.yOffset + 1
        if cache.yOffset >= cache.height then
            cache.yOffset = 0
            cache.xOffset = cache.xOffset + 1
            if cache.xOffset >= cache.width then
                cache.xOffset = 0
                cache.zIndex = cache.zIndex + 1
            end
        end
    end
    return processed
end

-- The scan cache of the descriptor's zone, created on first use and restarted when it is out of date, advanced by
-- at most `budget` squares (0 only checks whether it is out of date). Returns the cache and the number of squares
-- visited, or nil for a zone without an envelope (a map room outside any building).
function Envelope.refresh(config, descriptor, nowHours, budget)
    if not Places.hasEnvelope(descriptor) then
        return nil, 0
    end
    local cache = caches[descriptor.key]
    if not cache then
        cache = { key = descriptor.key, dirty = true }
        caches[descriptor.key] = cache
    end
    cache.lastSeenHour = nowHours
    if descriptor.kind == "player" then
        cache.anchorSquare = descriptor.anchorSquare or cache.anchorSquare
        local expected = math.max(1, tonumber(descriptor.area) or 1)
        if cache.complete and expected ~= cache.expectedSquares then
            cache.dirty = true
        end
    end
    if cache.complete and cache.builtHour then
        local age = nowHours - cache.builtHour
        local refreshAfter = cache.partial and config.EnvelopeRetryHours or config.EnvelopeRefreshHours
        if age < 0 or age >= refreshAfter then
            cache.dirty = true
        end
    end
    if cache.dirty then
        resetScan(cache, descriptor, nowHours)
    end
    local visited = 0
    budget = math.floor(tonumber(budget) or 0)
    if not cache.complete and budget > 0 then
        if cache.scanMode == "player" then
            visited = advancePlayerScan(cache, nowHours, budget)
        else
            visited = advanceBuildingScan(cache, nowHours, budget)
        end
    end
    return cache, visited
end

-- The leaks of the zone's outer wall right now (Leak.summarize), read again from every known opening, plus scan
-- figures: complete, partial, openingCount, squaresScanned, buildingSquaresSeen, roomCount, edgeCount. An opening
-- that is gone or no longer in the outer wall marks the zone for a rescan.
function Envelope.leaks(cache)
    local openings = {}
    local invalid = false
    for _, record in ipairs(cache.openings or {}) do
        local object = record.object
        if not object:getSquare() or not Openings.isExterior(object, cache.key) then
            invalid = true
        else
            local opening = Openings.read(object, record.kind)
            opening.roomKey = record.roomKey
            openings[#openings + 1] = opening
        end
    end
    if invalid then
        cache.dirty = true
    end
    local info = Leak.summarize(openings)
    local edgeCount, roomCount = 0, 0
    for _ in pairs(cache.edgeMap or {}) do
        edgeCount = edgeCount + 1
    end
    for _ in pairs(cache.roomNodes or {}) do
        roomCount = roomCount + 1
    end
    info.complete = cache.complete == true
    info.partial = cache.partial == true
    info.openingCount = #(cache.openings or {})
    info.squaresScanned = cache.squaresScanned or 0
    info.buildingSquaresSeen = cache.buildingSquaresSeen or 0
    info.missingSquares = cache.missingSquares or 0
    info.roomCount = roomCount
    info.edgeCount = edgeCount
    return info
end

-- The room graph for Rooms.advanceBuilding: { rooms = { [roomKey] = { area, z } }, edges = { ... } }. Edges are
-- sorted by key, so rooms always share heat in the same order, and each inner door's state is read again.
function Envelope.model(cache)
    local edges = {}
    local seen = {}
    for key, edge in pairs(cache.edgeMap or {}) do
        local openDoors = 0
        for _, door in ipairs(edge.doors) do
            if door:IsOpen() then
                openDoors = openDoors + 1
            end
        end
        edges[#edges + 1] = { key = key, a = edge.a, b = edge.b, passages = edge.passages, doors = #edge.doors,
            openDoors = openDoors, walls = edge.walls, learned = cache.learnedEdges[key] ~= nil }
        seen[key] = true
    end
    for key, edge in pairs(cache.learnedEdges or {}) do
        if not seen[key] then
            edges[#edges + 1] = { key = key, a = edge.a, b = edge.b, learned = true }
        end
    end
    table.sort(edges, function(x, y) return x.key < y.key end)
    return { complete = cache.complete == true, rooms = cache.roomNodes or {}, edges = edges }
end

-- Records that a player walked from one room of the zone to another on a different floor (stairs), which joins
-- them even though the scan found no edge between them.
function Envelope.learnTransition(zoneKey, roomA, roomB)
    local cache = caches[zoneKey]
    if not cache or not roomA or not roomB or roomA == roomB then
        return
    end
    local key, first, second = pairKey(roomA, roomB)
    cache.learnedEdges = cache.learnedEdges or {}
    cache.learnedEdges[key] = { a = first, b = second }
end

-- The leaks within ScanRadius squares of `square` on its floor (the original's nearby scan): doors and windows in
-- the outer wall of `zoneKey`, frames not counted. { leakScore, openDoors, openWindows }.
function Envelope.nearby(config, square, zoneKey)
    local cell = getCell()
    if not cell or not square then
        return { leakScore = 0, openDoors = 0, openWindows = 0 }
    end
    local radius = config.ScanRadius
    local cx, cy, z = square:getX(), square:getY(), square:getZ()
    local seen = {}
    local openings = {}
    for x = cx - radius, cx + radius do
        for y = cy - radius, cy + radius do
            local objects = nil
            local here = cell:getGridSquare(x, y, z)
            if here then
                objects = here:getSpecialObjects()
            end
            for index = 0, listSize(objects) - 1 do
                local object = objects:get(index)
                if object and not seen[object] and Openings.isExterior(object, zoneKey) then
                    seen[object] = true
                    local kind = Openings.kind(object)
                    if kind == "door" or kind == "window" then
                        openings[#openings + 1] = Openings.read(object, kind)
                    end
                end
            end
        end
    end
    local summary = Leak.summarize(openings)
    return { leakScore = summary.leakScore, openDoors = summary.openDoors, openWindows = summary.openWindows }
end

-- The cache of a zone, or nil.
function Envelope.get(zoneKey)
    return caches[zoneKey]
end

-- Drops caches beyond `maximum`, the least recently used first, never one in `keep` (zone key -> true).
function Envelope.prune(maximum, keep)
    local records = {}
    for key, cache in pairs(caches) do
        if not keep[key] then
            records[#records + 1] = { key = key, hour = tonumber(cache.lastSeenHour) or -1 }
        end
    end
    local excess = #records - maximum
    if excess <= 0 then
        return
    end
    table.sort(records, function(a, b)
        if a.hour ~= b.hour then
            return a.hour < b.hour
        end
        return a.key < b.key
    end)
    for index = 1, excess do
        caches[records[index].key] = nil
    end
end

function Envelope.clear()
    caches = {}
end

return Envelope
