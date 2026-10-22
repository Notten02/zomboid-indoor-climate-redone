-- The devices in the world: finding them, what powers them, and the list of the ones switched on.
--
-- A device is one of the mod's items placed on the ground (an IsoWorldInventoryObject). Its state lives in the
-- item's mod data under the original mod's field names (ICLHeaterActive, ICLHeaterFuelHour, the propane tank), so
-- devices in existing saves keep it. The server (or a single-player game) owns that state; a multiplayer client
-- learns it from the server (see the server's Appliances and the client's DeviceHeat).
--
-- The list holds every device known to be switched on, as plain records { key, x, y, z, fullType }, and is what
-- Heater.adjust reads. On a server it is everything the server switched on or found switched on; on a client, what
-- the server reported and what the client saw on squares it loaded.
--
-- Game adapter.
--
--   Devices.profileOf(object), Devices.isDevice(object), Devices.isOn(object), Devices.modData(object)
--   Devices.on(square, fullType)              the device object on a square (of that type), or nil
--   Devices.at(x, y, z, fullType)             the same by coordinates, and the square
--   Devices.canRun(object)                    electricity at its square, or propane in its tank
--   Devices.poweringGenerator(square, record) the generator an electric device draws on, or nil
--   Devices.track(object) / Devices.forget(key) / Devices.get(key) / Devices.list() / Devices.clear()
--   Devices.see(square)                       tracks or forgets every device on a square by its state
--   Devices.adjust(square, baseC, leakScore, config)   Heater.adjust with the switched-on devices
--   Devices.request(player, command, args)    a player's device command: to the server, or handled here
--   Devices.tankFuel(item), Devices.findFullTank(container), Devices.findItem(container, id)

local Heater = require("IndoorClimateRedone/Heater")
local Propane = require("IndoorClimateRedone/Propane")
local Sync = require("IndoorClimateRedone/Sync")

local Devices = {}

-- Client commands (args: x, y, z, fullType and below) and the server's state message (see Devices.stateArgs).
Devices.SWITCH = "device_switch"   -- active = true / false
Devices.TANK = "device_tank"       -- action = "insert" (tankId) / "remove"
Devices.STATE = "device_state"

-- A generator powers devices within this many tiles and floors, as in the original.
Devices.GENERATOR_RADIUS = 20
Devices.GENERATOR_FLOORS = 3

-- key -> record
local records = {}
local list = nil
-- Bumped on every change to the list (caches compare it).
Devices.version = 0

local function changed()
    list = nil
    Devices.version = Devices.version + 1
end

function Devices.key(x, y, z, fullType)
    return x .. ":" .. y .. ":" .. z .. ":" .. tostring(fullType)
end

local function itemOf(object)
    return object and object.getItem and object:getItem() or nil
end

function Devices.profileOf(object)
    local item = itemOf(object)
    return item and Heater.profile(item:getFullType()) or nil
end

function Devices.isDevice(object)
    return object ~= nil and instanceof(object, "IsoWorldInventoryObject") and Devices.profileOf(object) ~= nil
end

---@return table|nil
function Devices.modData(object)
    local item = itemOf(object)
    return item and item:getModData() or nil
end

function Devices.isOn(object)
    local modData = Devices.modData(object)
    return modData ~= nil and modData.ICLHeaterActive == true
end

local function scan(objects, fullType)
    if not objects then
        return nil
    end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if Devices.isDevice(object) and (not fullType or itemOf(object):getFullType() == fullType) then
            return object
        end
    end
    return nil
end

function Devices.on(square, fullType)
    if not square then
        return nil
    end
    return scan(square:getWorldObjects(), fullType) or scan(square:getObjects(), fullType)
        or scan(square:getSpecialObjects(), fullType)
end

function Devices.at(x, y, z, fullType)
    local square = getCell():getGridSquare(x, y, z)
    return Devices.on(square, fullType), square
end

-- Generator power at the square, or grid power in a room (the original's rule).
function Devices.hasElectricity(square)
    if not square then
        return false
    end
    return square:haveElectricity() == true or (square:hasGridPower() == true and square:isInARoom() == true)
end

function Devices.canRun(object)
    local profile = Devices.profileOf(object)
    if Heater.usesPropane(profile) then
        return Propane.hasFuel(Devices.modData(object))
    end
    return Devices.hasElectricity(object:getSquare())
end

function Devices.generatorUsable(generator, square)
    if not generator or not square or generator:getObjectIndex() == -1 or not generator:isActivated()
        or not generator:isConnected() or generator:getFuel() <= 0 then
        return false
    end
    local at = generator:getSquare()
    if not at or math.abs(at:getZ() - square:getZ()) > Devices.GENERATOR_FLOORS then
        return false
    end
    local dx, dy = at:getX() - square:getX(), at:getY() - square:getY()
    return dx * dx + dy * dy <= Devices.GENERATOR_RADIUS * Devices.GENERATOR_RADIUS
end

-- The nearest usable generator in reach of `square`. The answer is kept on `record` while it stays usable.
function Devices.poweringGenerator(square, record)
    if not square then
        return nil
    end
    if record and Devices.generatorUsable(record.generator, square) then
        return record.generator
    end
    local cell = getCell()
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local radius = Devices.GENERATOR_RADIUS
    local nearest, nearestDistance = nil, radius * radius + 1
    for dz = -Devices.GENERATOR_FLOORS, Devices.GENERATOR_FLOORS do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local distance = dx * dx + dy * dy
                if distance < nearestDistance then
                    local other = cell:getGridSquare(x + dx, y + dy, z + dz)
                    local generator = other and other:getGenerator() or nil
                    if Devices.generatorUsable(generator, square) then
                        nearest, nearestDistance = generator, distance
                    end
                end
            end
        end
    end
    if record then
        record.generator = nearest
    end
    return nearest
end

local function where(object)
    local square = object:getSquare()
    local item = itemOf(object)
    if not square or not item then
        return nil
    end
    return square:getX(), square:getY(), square:getZ(), item:getFullType()
end

-- Puts a device on the list (it is switched on). Returns its record.
function Devices.track(object)
    local x, y, z, fullType = where(object)
    if not x then
        return nil
    end
    local key = Devices.key(x, y, z, fullType)
    local record = records[key]
    if not record then
        record = { key = key, x = x, y = y, z = z, fullType = fullType }
        records[key] = record
        changed()
    end
    return record
end

function Devices.forget(key)
    if records[key] then
        records[key] = nil
        changed()
    end
end

function Devices.keyOf(object)
    local x, y, z, fullType = where(object)
    return x and Devices.key(x, y, z, fullType) or nil
end

function Devices.get(key)
    return records[key]
end

-- The switched-on devices as an array, in key order (so sums come out the same every time).
function Devices.list()
    if not list then
        list = {}
        for _, record in pairs(records) do
            list[#list + 1] = record
        end
        table.sort(list, function(a, b) return a.key < b.key end)
    end
    return list
end

function Devices.clear()
    records = {}
    changed()
end

-- Tracks the switched-on devices on `square` and forgets the ones switched off. Returns the devices it found.
function Devices.see(square, found)
    found = found or {}
    if not square then
        return found
    end
    local seen = {}
    for _, objects in ipairs({ square:getWorldObjects(), square:getObjects(), square:getSpecialObjects() }) do
        for index = 0, objects:size() - 1 do
            local object = objects:get(index)
            if not seen[object] and Devices.isDevice(object) then
                seen[object] = true
                found[#found + 1] = object
                if Devices.isOn(object) then
                    Devices.track(object)
                else
                    Devices.forget(Devices.keyOf(object))
                end
            end
        end
    end
    return found
end

-- Every square within `radius` of the given squares, on their floor and `floors` floors above and below.
function Devices.around(centres, radius, floors, fn)
    local cell = getCell()
    local done = {}
    for _, centre in ipairs(centres) do
        local cx, cy, cz = centre:getX(), centre:getY(), centre:getZ()
        for dz = -floors, floors do
            for dx = -radius, radius do
                for dy = -radius, radius do
                    local square = cell:getGridSquare(cx + dx, cy + dy, cz + dz)
                    if square and not done[square] then
                        done[square] = true
                        fn(square)
                    end
                end
            end
        end
    end
end

function Devices.adjust(square, baseC, leakScore, config)
    if not square then
        local base = tonumber(baseC) or 15
        return base, 0, 0, 0, Heater.retention(leakScore, config)
    end
    return Heater.adjust(Devices.list(), square:getX(), square:getY(), square:getZ(), baseC, leakScore, config)
end

-- The state message for a device: where it is, whether it is on, its propane tank and the hour it was switched on.
function Devices.stateArgs(object)
    local x, y, z, fullType = where(object)
    local modData = Devices.modData(object) or {}
    local present, fuel = Propane.state(modData)
    return { x = x, y = y, z = z, fullType = fullType, active = modData.ICLHeaterActive == true,
        fuelHour = tonumber(modData.ICLHeaterFuelHour), tankPresent = present, tankFuel = fuel }
end

-- The fill (0 to 1) of a propane tank item; 0 for anything else.
function Devices.tankFuel(item)
    if not item or item:getFullType() ~= Propane.TANK_TYPE then
        return 0
    end
    return math.max(0, math.min(1, tonumber(item:getCurrentUsesFloat()) or 0))
end

local function walk(container, match)
    local items = container and container:getItems() or nil
    if not items then
        return nil
    end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        if match(item) then
            return item
        end
        local inner = instanceof(item, "InventoryContainer") and item:getInventory() or nil
        local found = inner and walk(inner, match) or nil
        if found then
            return found
        end
    end
    return nil
end

-- A propane tank with fuel in it, in the container or bags inside it, or nil.
function Devices.findFullTank(container)
    return walk(container, function(item) return Devices.tankFuel(item) > Propane.EMPTY end)
end

-- The item with this ID in the container or bags inside it, or nil.
function Devices.findItem(container, id)
    local wanted = tonumber(id)
    if not wanted then
        return nil
    end
    return walk(container, function(item) return item:getID() == wanted end)
end

-- fn(player, command, args) that handles device commands where the state is owned (server, single player).
local handler = nil

function Devices.serve(fn)
    handler = fn
end

-- Sends a player's device command to the server, or in single player handles it at once.
function Devices.request(player, command, args)
    if isClient() then
        sendClientCommand(player, Sync.MODULE, command, args)
    elseif handler then
        handler(player, command, args)
    end
end

return Devices
