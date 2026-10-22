-- Leaks: how much air the openings in a building's outer wall let through, and how freely two rooms inside share
-- heat.
--
-- An opening is a plain table read from the game by the envelope scan:
--   { kind = "door" | "window" | "windowFrame", roomKey = <room it belongs to, or nil>,
--     open = bool, smashed = bool, glassRemoved = bool,  -- windows
--     hasWindow = bool,                                  -- frames: a window still sits in it
--     barricades = { <barricade>, <barricade> } }        -- windows and frames: one per side, either may be missing
-- A barricade is { metalBar = bool, metal = bool, planks = n }.
--
-- Each open opening adds a weight: an open door 1.0, a smashed or glassless window 0.85, an open window 0.70, an
-- empty frame 0.85. Barricades on a window or frame multiply its weight (planks 0.60 / 0.40 / 0.25 / 0.12 for 1-4,
-- metal sheet 0.05, metal bars 0.30, both sides multiplied). Doors ignore barricades. A room's leak score is the sum
-- of its weights, capped at 1.
--
-- Pure: openings and edges are plain tables.

local Config = require("IndoorClimateRedone/Config")

local clamp = Config.clamp

local Leak = {}

Leak.DOOR = 1.0
Leak.BROKEN_WINDOW = 0.85
Leak.OPEN_WINDOW = 0.70
Leak.EMPTY_FRAME = 0.85
Leak.PLANKS = { 0.60, 0.40, 0.25, 0.12 }
Leak.METAL_SHEET = 0.05
Leak.METAL_BARS = 0.30

-- Heat exchange rates per hour between two rooms of a building, by what joins them.
Leak.EDGE_PASSAGE = 3.0
Leak.EDGE_OPEN_DOOR = 3.0
Leak.EDGE_CLOSED_DOOR = 0.10
Leak.EDGE_LEARNED = 0.80
Leak.EDGE_WALL = 0.02

-- The share of air one barricade lets through (1 when there is none).
function Leak.barricadeFactor(barricade)
    if type(barricade) ~= "table" then
        return 1.0
    end
    if barricade.metalBar then
        return Leak.METAL_BARS
    end
    if barricade.metal then
        return Leak.METAL_SHEET
    end
    local planks = math.max(0, math.min(4, math.floor(tonumber(barricade.planks) or 0)))
    return Leak.PLANKS[planks] or 1.0
end

local function barricadesFactor(opening)
    local barricades = opening.barricades or {}
    return Leak.barricadeFactor(barricades[1]) * Leak.barricadeFactor(barricades[2])
end

-- The leak weight of one opening, 0 when it is closed.
function Leak.weight(opening)
    local kind = opening and opening.kind
    if kind == "door" then
        return opening.open and Leak.DOOR or 0
    end
    if kind == "windowFrame" then
        if opening.hasWindow then
            return 0
        end
        return Leak.EMPTY_FRAME * barricadesFactor(opening)
    end
    if kind ~= "window" then
        return 0
    end
    local base = 0
    if opening.smashed or opening.glassRemoved then
        base = Leak.BROKEN_WINDOW
    elseif opening.open then
        base = Leak.OPEN_WINDOW
    end
    if base <= 0 then
        return 0
    end
    return base * barricadesFactor(opening)
end

-- The leaks of a list of outer-wall openings:
--   { leakScore = 0..1, openDoors = n, openWindows = n,
--     perRoom = { [roomKey] = { leakUnits, leakScore, openDoors, openWindows } } }
-- Frames count as windows. Openings without a roomKey count for the building only.
function Leak.summarize(openings)
    local units, doors, windows = 0, 0, 0
    local perRoom = {}
    for _, opening in ipairs(openings or {}) do
        local weight = Leak.weight(opening)
        if weight > 0 then
            units = units + weight
            local room = nil
            if opening.roomKey then
                room = perRoom[opening.roomKey]
                if not room then
                    room = { leakUnits = 0, leakScore = 0, openDoors = 0, openWindows = 0 }
                    perRoom[opening.roomKey] = room
                end
                room.leakUnits = room.leakUnits + weight
            end
            if opening.kind == "door" then
                doors = doors + 1
                if room then
                    room.openDoors = room.openDoors + 1
                end
            else
                windows = windows + 1
                if room then
                    room.openWindows = room.openWindows + 1
                end
            end
        end
    end
    for _, room in pairs(perRoom) do
        room.leakScore = clamp(room.leakUnits, 0, 1)
    end
    return { leakScore = clamp(units, 0, 1), openDoors = doors, openWindows = windows, perRoom = perRoom }
end

-- While a building's scan is unfinished, the leaks found near the player (`nearby`: leakScore, openDoors,
-- openWindows) raise the summary and the player's room to at least those values. Changes `summary` in place.
function Leak.mergeNearby(summary, roomKey, nearby)
    summary.leakScore = math.max(summary.leakScore, nearby.leakScore)
    summary.openDoors = math.max(summary.openDoors, nearby.openDoors)
    summary.openWindows = math.max(summary.openWindows, nearby.openWindows)
    if roomKey then
        local room = summary.perRoom[roomKey] or { leakScore = 0, openDoors = 0, openWindows = 0 }
        room.leakScore = math.max(room.leakScore, nearby.leakScore)
        room.openDoors = math.max(room.openDoors, nearby.openDoors)
        room.openWindows = math.max(room.openWindows, nearby.openWindows)
        summary.perRoom[roomKey] = room
    end
    return summary
end

local function isEmpty(t)
    for _ in pairs(t) do
        return false
    end
    return true
end

-- The leaks of one room: its own entry, else the whole building's when no opening could be tied to any room (the
-- entry is then stored for the room), else none.
function Leak.forRoom(summary, roomKey)
    local room = roomKey and summary.perRoom[roomKey] or nil
    if not room and summary.leakScore > 0 and isEmpty(summary.perRoom) then
        room = { leakScore = summary.leakScore, openDoors = summary.openDoors, openWindows = summary.openWindows }
        if roomKey then
            summary.perRoom[roomKey] = room
        end
    end
    return room or { leakScore = 0, openDoors = 0, openWindows = 0 }
end

-- The heat exchange rate per hour between two rooms. `edge` counts what joins them:
--   { passages = n, doors = n, openDoors = n, walls = n, learned = bool }
-- An open passage or open door joins them fully, a closed door a little, a link seen only because a player walked
-- it (stairs) more, a shared wall barely.
function Leak.edgeRate(edge)
    if not edge then
        return 0
    end
    if (tonumber(edge.passages) or 0) > 0 then
        return Leak.EDGE_PASSAGE
    end
    if (tonumber(edge.openDoors) or 0) > 0 then
        return Leak.EDGE_OPEN_DOOR
    end
    if (tonumber(edge.doors) or 0) > 0 then
        return Leak.EDGE_CLOSED_DOOR
    end
    if edge.learned then
        return Leak.EDGE_LEARNED
    end
    if (tonumber(edge.walls) or 0) > 0 then
        return Leak.EDGE_WALL
    end
    return 0
end

return Leak
