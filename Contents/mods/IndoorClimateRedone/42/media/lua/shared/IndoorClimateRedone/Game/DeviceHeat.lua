-- The heat source each switched-on heater places, and on a multiplayer client what it knows about the devices.
--
-- As in the original, a heater (not the fan) that is switched on and can run places a game heat source (IsoHeatSource)
-- at its square with the heater's radius and source temperature, so the game's own air near it warms. Sources are
-- kept for heaters within their radius + 6 tiles of a player on the same floor, and refreshed every game minute and
-- whenever the list of switched-on devices changed. The original placed them on the clients only; in multiplayer the
-- server works out body warmth from its own air, so they are placed there too: a client places them for its local
-- players, a dedicated server for every online player. They are registered in HeatSources, so the room simulation
-- reads the game's air without them.
--
-- A multiplayer client keeps the item mod data and the device list in step with the server's state messages
-- (Devices.STATE), and checks the squares it loads and the squares around its players every game minute.
--
-- Game adapter.
--
--   DeviceHeat.refresh(squares)  places, moves and removes the heat sources for players on these squares
--   DeviceHeat.changed()         whether the device list changed since the last refresh
--   DeviceHeat.receive(args)     a state message from the server (multiplayer client)
--   DeviceHeat.look(squares)     checks the squares around these players (multiplayer client)
--   DeviceHeat.clear()

local Heater = require("IndoorClimateRedone/Heater")
local Propane = require("IndoorClimateRedone/Propane")
local Devices = require("IndoorClimateRedone/Game/Devices")
local HeatSources = require("IndoorClimateRedone/Game/HeatSources")

local DeviceHeat = {}

DeviceHeat.EXTRA_TILES = 6
DeviceHeat.LOOK_RADIUS = Heater.MAX_RADIUS + 1

-- key -> owner of the heat source placed for that device
local placed = {}
local placedVersion = nil

local function near(record, squares, radius)
    for _, square in ipairs(squares) do
        if square:getZ() == record.z then
            local dx, dy = square:getX() - record.x, square:getY() - record.y
            if dx * dx + dy * dy <= radius * radius then
                return true
            end
        end
    end
    return false
end

function DeviceHeat.refresh(squares)
    local wanted = {}
    for _, record in ipairs(Devices.list()) do
        local profile = Heater.profile(record.fullType)
        if profile and profile.nativeHeatSource ~= false and near(record, squares, profile.radius + DeviceHeat.EXTRA_TILES) then
            local object, square = Devices.at(record.x, record.y, record.z, record.fullType)
            if object and Devices.canRun(object) then
                local owner = placed[record.key] or ("device:" .. record.key)
                HeatSources.place(owner, square, profile.radius, profile.sourceTemperature)
                wanted[record.key] = owner
            end
        end
    end
    for key, owner in pairs(placed) do
        if not wanted[key] then
            HeatSources.remove(owner)
        end
    end
    placed = wanted
    placedVersion = Devices.version
end

function DeviceHeat.changed()
    return placedVersion ~= Devices.version
end

local function coordinate(value)
    local number = tonumber(value)
    return number and math.floor(number) or nil
end

-- Returns whether the message was a valid one; the caller refreshes the sources.
function DeviceHeat.receive(args)
    if type(args) ~= "table" or not Heater.profile(args.fullType) then
        return false
    end
    local x, y, z = coordinate(args.x), coordinate(args.y), coordinate(args.z)
    if not x or not y or not z then
        return false
    end
    local object = Devices.at(x, y, z, args.fullType)
    local modData = Devices.modData(object)
    if modData then
        if args.active == true then
            modData.ICLHeaterActive = true
            modData.ICLHeaterFuelHour = tonumber(args.fuelHour)
        else
            modData.ICLHeaterActive = nil
            modData.ICLHeaterFuelHour = nil
        end
        if Heater.usesPropane(Heater.profile(args.fullType)) and args.tankPresent ~= nil then
            Propane.set(modData, args.tankPresent == true, args.tankFuel)
        end
    end
    if args.active == true and object then
        Devices.track(object)
    else
        Devices.forget(Devices.key(x, y, z, args.fullType))
    end
    return true
end

function DeviceHeat.look(squares)
    Devices.around(squares, DeviceHeat.LOOK_RADIUS, 0, Devices.see)
end

function DeviceHeat.clear()
    for _, owner in pairs(placed) do
        HeatSources.remove(owner)
    end
    placed = {}
    placedVersion = nil
end

return DeviceHeat
