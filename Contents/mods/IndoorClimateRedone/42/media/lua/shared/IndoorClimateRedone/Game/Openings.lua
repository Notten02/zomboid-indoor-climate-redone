-- Doors, windows and window frames: what kind an object is, and its state as the plain opening table Leak weighs.
--
-- Game adapter: reads IsoDoor, IsoWindow, IsoWindowFrame and IsoThumpable objects. The rules are the original mod's
-- (ICL_BuildingEnvelope). Window frames lack some window methods, so every optional call is guarded.

local Places = require("IndoorClimateRedone/Game/Places")

local Openings = {}

local function listSize(list)
    return list and tonumber(list:size()) or 0
end

local function hasSpriteFlag(object, flagName)
    local properties = object.getProperties and object:getProperties() or nil
    if not properties or not properties.has then
        return false
    end
    local flag = IsoFlagType and IsoFlagType[flagName] or nil
    if flag and properties:has(flag) then
        return true
    end
    return properties:has(flagName) == true
end

-- "door", "window", "windowFrame", or nil for anything else.
function Openings.kind(object)
    if not object or not instanceof then
        return nil
    end
    if instanceof(object, "IsoDoor") then
        return "door"
    end
    if instanceof(object, "IsoWindow") then
        return "window"
    end
    if instanceof(object, "IsoWindowFrame") then
        return "windowFrame"
    end
    if not instanceof(object, "IsoThumpable") then
        return nil
    end
    if object.isDoor and object:isDoor() then
        return "door"
    end
    if hasSpriteFlag(object, "WindowN") or hasSpriteFlag(object, "WindowW") then
        return "windowFrame"
    end
    if (object.isWindow and object:isWindow()) or (object.isWindowN and object:isWindowN())
        or (object.isWindowW and object:isWindowW()) then
        return "window"
    end
    if hasSpriteFlag(object, "windowN") or hasSpriteFlag(object, "windowW") then
        return "window"
    end
    return nil
end

local function readBarricade(barricade)
    if not barricade then
        return nil
    end
    return {
        metalBar = barricade.isMetalBar ~= nil and barricade:isMetalBar() == true,
        metal = barricade.isMetal ~= nil and barricade:isMetal() == true,
        planks = barricade.getNumPlanks and tonumber(barricade:getNumPlanks()) or 0,
    }
end

local function readBarricades(object)
    local same = object.getBarricadeOnSameSquare and object:getBarricadeOnSameSquare() or nil
    local opposite = object.getBarricadeOnOppositeSquare and object:getBarricadeOnOppositeSquare() or nil
    return { readBarricade(same), readBarricade(opposite) }
end

-- The object's state as a Leak opening table (without roomKey). `kind` defaults to Openings.kind(object).
function Openings.read(object, kind)
    kind = kind or Openings.kind(object)
    if kind == "door" then
        return { kind = kind, open = object:IsOpen() == true }
    end
    if kind == "windowFrame" then
        local hasWindow = object.hasWindow ~= nil and object:hasWindow() == true
        return { kind = kind, hasWindow = hasWindow, barricades = not hasWindow and readBarricades(object) or nil }
    end
    if kind ~= "window" then
        return { kind = kind }
    end
    local opening = {
        kind = kind,
        smashed = object.isSmashed ~= nil and object:isSmashed() == true,
        glassRemoved = object.isGlassRemoved ~= nil and object:isGlassRemoved() == true,
    }
    -- Only a whole window is asked whether it is open, as the original does.
    opening.open = not opening.smashed and not opening.glassRemoved and object:IsOpen() == true
    if opening.smashed or opening.glassRemoved or opening.open then
        opening.barricades = readBarricades(object)
    end
    return opening
end

-- The zone keys on the two sides of a door or window, or nil when either square is missing.
local function sideKeys(object)
    if not object or not object.getSquare or not object.getOppositeSquare then
        return nil
    end
    local square = object:getSquare()
    local opposite = object:getOppositeSquare()
    if not square or not opposite then
        return nil
    end
    local a, b = Places.describe(square), Places.describe(opposite)
    return a, b
end

-- True when the object is in the outer wall of the zone: exactly one of its two sides belongs to `zoneKey`.
function Openings.isExterior(object, zoneKey)
    if not zoneKey then
        return false
    end
    local a, b = sideKeys(object)
    if a == nil and b == nil then
        return false
    end
    local keyA = a and a.key or nil
    local keyB = b and b.key or nil
    return (keyA == zoneKey and keyB ~= zoneKey) or (keyB == zoneKey and keyA ~= zoneKey)
end

-- The room inside the zone that an outer-wall object belongs to, or nil.
function Openings.interiorRoomKey(object, zoneKey)
    local a, b = sideKeys(object)
    if a and a.key == zoneKey and (not b or b.key ~= zoneKey) then
        return Places.roomKey(a)
    end
    if b and b.key == zoneKey and (not a or a.key ~= zoneKey) then
        return Places.roomKey(b)
    end
    return nil
end

-- Calls visitor(object) for every object on the square, special objects, its door and its window (an object may
-- come more than once, and may be nil). In 42.21 getDoor and getWindow take an edge, not the original's boolean;
-- the square's object lists already hold every door and window, so only the no-argument lookups are used.
function Openings.visit(square, visitor)
    if not square then
        return
    end
    local objects = square:getObjects()
    for index = 0, listSize(objects) - 1 do
        visitor(objects:get(index))
    end
    objects = square:getSpecialObjects()
    for index = 0, listSize(objects) - 1 do
        visitor(objects:get(index))
    end
    visitor(square:getIsoDoor())
    visitor(square:getWindow())
end

local function joins(object, squareA, squareB)
    if not object.getSquare or not object.getOppositeSquare then
        return false
    end
    local square = object:getSquare()
    local opposite = object:getOppositeSquare()
    return (square == squareA and opposite == squareB) or (square == squareB and opposite == squareA)
end

-- The door between two neighbouring squares, or nil.
function Openings.doorBetween(squareA, squareB)
    local found = nil
    local seen = {}
    local function inspect(object)
        if found or not object or seen[object] then
            return
        end
        seen[object] = true
        if Openings.kind(object) == "door" and joins(object, squareA, squareB) then
            found = object
        end
    end
    Openings.visit(squareA, inspect)
    Openings.visit(squareB, inspect)
    return found
end

return Openings
