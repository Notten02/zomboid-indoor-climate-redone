-- Where a square is, as the climate sees it: the map building and room it belongs to, or the player-built room.
--
-- Game adapter: reads squares, RoomDefs, BuildingDefs and world regions. A descriptor is a plain table plus the game
-- objects the envelope scan needs:
--   map room in a building  { key = <building key>, roomKey = "vanilla:<id>", legacyKey = roomKey, kind = "vanilla",
--                             area = w * h, z, buildingDef, buildingX, buildingY, buildingW, buildingH, anchorSquare }
--   map room, no building   { key = roomKey = legacyKey = "vanilla:<id>", kind = "vanilla", area = room area, z }
--   player-built room       { key = roomKey = "player:region:<id>:z<z>", kind = "player", area = region size, z,
--                             regionId, anchorSquare }
-- Outdoors, and in player-built spaces that are not fully roofed, there is no descriptor.
--
-- The rules are the original mod's (ICL_Core.getRoomDescriptor), so its keys stay valid. Map room and building keys
-- are the same on a server and its clients; world region IDs are not.

local Rooms = require("IndoorClimateRedone/Rooms")

local Places = {}

local function nonEmpty(id)
    return id ~= nil and id ~= "" and id
end

local function mapRoom(square)
    if not square:isInARoom() then
        return nil
    end
    local roomDef = square:getRoomDef()
    local room = nil
    if not roomDef then
        room = square:getRoom()
        roomDef = room and room:getRoomDef() or nil
    end
    if not roomDef then
        return nil
    end

    local roomKey = Rooms.vanillaRoomKey(nonEmpty(roomDef:getIDString()) or tostring(roomDef:getID()))
    room = room or square:getRoom()
    local building = square:getBuilding()
    if not building and room then
        building = room:getBuilding()
    end
    local buildingDef = building and building:getDef() or nil
    if not buildingDef then
        return {
            key = roomKey,
            roomKey = roomKey,
            legacyKey = roomKey,
            kind = "vanilla",
            area = math.max(1, tonumber(roomDef:getArea()) or 1),
            z = square:getZ(),
        }
    end

    local x = tonumber(buildingDef:getX())
    local y = tonumber(buildingDef:getY())
    local w = tonumber(buildingDef:getW())
    local h = tonumber(buildingDef:getH())
    local key
    if x and y and w and h then
        key = Rooms.buildingKey(x, y, w, h)
    else
        key = Rooms.buildingIdKey(nonEmpty(buildingDef:getIDString()) or tostring(building:getID()))
    end
    return {
        key = key,
        roomKey = roomKey,
        legacyKey = roomKey,
        kind = "vanilla",
        area = math.max(1, (w or 1) * (h or 1)),
        z = square:getZ(),
        buildingDef = buildingDef,
        buildingX = x,
        buildingY = y,
        buildingW = w,
        buildingH = h,
        anchorSquare = square,
    }
end

local function playerRoom(square)
    local region = square:getIsoWorldRegion()
    if not region or not region:isPlayerRoom() or not region:isFullyRoofed() then
        return nil
    end
    local z = tonumber(square:getZ()) or 0
    local regionId = region:getID()
    local id = regionId
    if id == nil then
        id = square:getRoomIDString()
        if not id or id == "" or id == "-1" then
            id = tostring(region)
        end
    end
    local key = Rooms.playerRoomKey(id, z)
    return {
        key = key,
        roomKey = key,
        kind = "player",
        area = math.max(1, tonumber(region:getSquareSize()) or 1),
        z = z,
        regionId = regionId,
        anchorSquare = square,
    }
end

-- The descriptor of the space `square` is in, or nil outdoors (and for a nil square).
function Places.describe(square)
    if not square then
        return nil
    end
    return mapRoom(square) or playerRoom(square)
end

-- The key of the thermal room a descriptor stands for: the map room within its building, or the whole space.
function Places.roomKey(descriptor)
    if not descriptor then
        return nil
    end
    return descriptor.roomKey or descriptor.legacyKey or descriptor.key
end

-- The zone key (building or space) of a square, or nil outdoors.
function Places.zoneKey(square)
    local descriptor = Places.describe(square)
    return descriptor and descriptor.key or nil
end

-- True when the descriptor has a scannable envelope: a player-built room, or a map room inside a building.
function Places.hasEnvelope(descriptor)
    return descriptor ~= nil
        and (descriptor.kind == "player" or (descriptor.kind == "vanilla" and descriptor.buildingDef ~= nil))
end

return Places
