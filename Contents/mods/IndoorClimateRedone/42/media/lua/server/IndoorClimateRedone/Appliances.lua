-- The devices on the server (or in a single-player game), which owns their state: switching them on and off for a
-- player, the propane heater's tank, the fuel they use and switching them off when they cannot run. The original
-- mod's rules:
--   - a player switches a device or handles its tank from within 3 tiles, on its floor;
--   - a device switches on only with electricity at its square (a generator, or the grid in a room) or, for the
--     propane heater, a tank with fuel in it;
--   - every game minute each switched-on device is checked: it switches off when it lost its power or ran out of
--     propane. A propane heater burns 0.025 of a tank an hour. With the grid off, an electric device draws on the
--     nearest generator within 20 tiles and 3 floors (the fan 0.20 L/h, the heaters HeaterGeneratorFuelPerHour),
--     and a generator that runs dry switches off with the devices on it. Time missed while unloaded counts up to
--     MaxElapsedHours;
--   - switched-on devices are found around players every 10 game minutes, and on every square that loads.
-- On a dedicated server, every change of a device's state goes out to all clients (Devices.STATE). A device that
-- was switched on and then picked up comes back switched off wherever it is put down.
--
--   Appliances.start(onChange)          at world load; onChange() runs after any device changed state
--   Appliances.command(player, command, args)
--   Appliances.update(nowHours, config) every game minute
--   Appliances.see(square)              a square loaded or an object was added
--   Appliances.removed(object)          an object is about to leave its square
--   Appliances.greet(player)            sends a (re)joining client the devices switched on near it

local Heater = require("IndoorClimateRedone/Heater")
local Propane = require("IndoorClimateRedone/Propane")
local Sync = require("IndoorClimateRedone/Sync")
local Devices = require("IndoorClimateRedone/Game/Devices")
local Power = require("IndoorClimateRedone/Game/Power")

local Appliances = {}

Appliances.REACH_TILES = 3
Appliances.DISCOVERY_RADIUS = Heater.MAX_RADIUS + 1
Appliances.DISCOVERY_MINUTES = 10
-- A (re)joining client is told about switched-on devices this close.
Appliances.GREET_TILES = 60

local onChange = nil
local minutes = 0

local function notify()
    if onChange then
        onChange()
    end
end

local function broadcast(object)
    if isServer() then
        sendServerCommand(Sync.MODULE, Devices.STATE, Devices.stateArgs(object))
    end
end

local function place(object)
    local square = object:getSquare()
    return square:getX() .. ":" .. square:getY() .. ":" .. square:getZ()
end

-- Switches a device on or off and tells everyone.
local function switch(object, on, nowHours)
    local modData = Devices.modData(object)
    if not modData then
        return
    end
    if on then
        modData.ICLHeaterActive = true
        modData.ICLHeaterFuelHour = nowHours
        modData.ICLDeviceAt = place(object)
        Devices.track(object)
    else
        modData.ICLHeaterActive = nil
        modData.ICLHeaterFuelHour = nil
        modData.ICLDeviceAt = nil
        Devices.forget(Devices.keyOf(object))
    end
    broadcast(object)
    notify()
end

local function worldHours()
    return getGameTime():getWorldAgeHours()
end

function Appliances.start(callback)
    onChange = callback
    minutes = 0
    Devices.clear()
end

local function coordinate(value)
    local number = tonumber(value)
    if not number or number ~= number then
        return nil
    end
    return math.floor(number)
end

local function inReach(player, square)
    local at = player:getCurrentSquare()
    if not at or at:getZ() ~= square:getZ() then
        return false
    end
    local dx, dy = player:getX() - square:getX(), player:getY() - square:getY()
    return dx * dx + dy * dy <= Appliances.REACH_TILES * Appliances.REACH_TILES
end

local function giveTank(player, fuel)
    local inventory = player:getInventory()
    local tank = instanceItem(Propane.TANK_TYPE)
    if not inventory or not tank then
        return false
    end
    ---@cast tank DrainableComboItem
    tank:setUsedDelta(math.max(0, math.min(1, fuel)))
    inventory:AddItem(tank)
    if isServer() then
        sendAddItemToContainer(inventory, tank)
    end
    return true
end

-- Unequipped first, as vanilla does: a tank held in the hands would otherwise stay there after leaving the inventory.
local function takeItem(player, item)
    local container = item:getContainer()
    if not container then
        return false
    end
    player:removeFromHands(item)
    container:Remove(item)
    if isServer() then
        sendRemoveItemFromContainer(container, item)
    end
    return true
end

local function tankAction(object, player, action, tankId, nowHours)
    local modData = Devices.modData(object)
    if not Heater.usesPropane(Devices.profileOf(object)) or not modData or not player:getInventory() then
        return false
    end
    local present, oldFuel = Propane.state(modData)
    if action == "insert" then
        local tank = Devices.findItem(player:getInventory(), tankId)
        local fuel = Devices.tankFuel(tank)
        if fuel <= Propane.EMPTY or not takeItem(player, tank) then
            return false
        end
        if present then
            giveTank(player, oldFuel)
        end
        if modData.ICLHeaterActive == true then
            switch(object, false, nowHours)
        end
        Propane.set(modData, true, fuel)
    elseif action == "remove" then
        if not present or not giveTank(player, oldFuel) then
            return false
        end
        if modData.ICLHeaterActive == true then
            switch(object, false, nowHours)
        end
        Propane.set(modData, false, 0)
    else
        return false
    end
    broadcast(object)
    notify()
    return true
end

-- A player's device command (from their client, or in single player straight from the menu). Returns true when
-- it changed something.
function Appliances.command(player, command, args)
    if type(args) ~= "table" or not player or not Heater.profile(args.fullType)
        or (command ~= Devices.SWITCH and command ~= Devices.TANK) then
        return false
    end
    local x, y, z = coordinate(args.x), coordinate(args.y), coordinate(args.z)
    if not x or not y or not z then
        return false
    end
    local object, square = Devices.at(x, y, z, args.fullType)
    if not object or not inReach(player, square) then
        return false
    end
    local nowHours = worldHours()
    if command == Devices.TANK then
        return tankAction(object, player, args.action, args.tankId, nowHours)
    end
    local on = args.active == true
    if on and not Devices.canRun(object) then
        return false
    end
    switch(object, on, nowHours)
    return true
end

local function syncGenerator(generator, refresh)
    generator:sync()
    if refresh then
        generator:setSurroundingElectricity()
    end
end

-- Uses `hours` of fuel for one switched-on device. Returns false when it switched the device off.
local function burn(object, square, record, hours, config, gridOn)
    local profile = Devices.profileOf(object)
    local modData = Devices.modData(object)
    if Heater.usesPropane(profile) then
        local _, before = Propane.state(modData)
        local hasFuel, remaining, changed = Propane.burn(modData, profile, hours)
        if changed and hasFuel and Propane.percent(before) ~= Propane.percent(remaining) then
            broadcast(object)
        end
        return hasFuel
    end
    local rate = Heater.generatorFuelPerHour(profile, config)
    if hours <= 0 or rate <= 0 or gridOn then
        return true
    end
    local generator = Devices.poweringGenerator(square, record)
    if not generator then
        return false
    end
    local remaining = (tonumber(generator:getFuel()) or 0) - rate * hours
    if remaining <= 0 then
        generator:setFuel(0)
        generator:setActivated(false)
        syncGenerator(generator, true)
        return false
    end
    generator:setFuel(remaining)
    syncGenerator(generator, false)
    return true
end

local function moved(object)
    local modData = Devices.modData(object)
    return modData ~= nil and modData.ICLDeviceAt ~= nil and modData.ICLDeviceAt ~= place(object)
end

-- Tracks the switched-on devices on a square; one that was picked up while on and put down here goes off.
function Appliances.see(square)
    local version = Devices.version
    for _, object in ipairs(Devices.see(square)) do
        if Devices.isOn(object) and moved(object) then
            switch(object, false, worldHours())
        end
    end
    if Devices.version ~= version then
        notify()
    end
end

function Appliances.removed(object)
    if Devices.isDevice(object) and object:getSquare() then
        local key = Devices.keyOf(object)
        if key and Devices.get(key) then
            Devices.forget(key)
            notify()
        end
    end
end

local function discover()
    local centres = {}
    local players = isServer() and getOnlinePlayers() or nil
    if players then
        for index = 0, players:size() - 1 do
            centres[#centres + 1] = players:get(index):getCurrentSquare()
        end
    else
        for index = 0, getNumActivePlayers() - 1 do
            local player = getSpecificPlayer(index)
            centres[#centres + 1] = player and player:getCurrentSquare() or nil
        end
    end
    Devices.around(centres, Appliances.DISCOVERY_RADIUS, 1, Appliances.see)
end

function Appliances.update(nowHours, config)
    minutes = minutes + 1
    if minutes >= Appliances.DISCOVERY_MINUTES then
        minutes = 0
        discover()
    end
    local gridOn = Power.grid()
    -- A copy: switching off changes the list.
    local records = {}
    for _, record in ipairs(Devices.list()) do
        records[#records + 1] = record
    end
    for _, record in ipairs(records) do
        local object, square = Devices.at(record.x, record.y, record.z, record.fullType)
        local modData = Devices.modData(object)
        if not object or not modData or modData.ICLHeaterActive ~= true then
            Devices.forget(record.key)
            notify()
        elseif not Devices.canRun(object) then
            switch(object, false, nowHours)
        else
            local last = tonumber(modData.ICLHeaterFuelHour) or nowHours
            local hours = math.max(0, math.min(config.MaxElapsedHours, nowHours - last))
            modData.ICLHeaterFuelHour = nowHours
            if not burn(object, square, record, hours, config, gridOn) then
                switch(object, false, nowHours)
            end
        end
    end
end

function Appliances.greet(player)
    local at = player:getCurrentSquare()
    if not at then
        return
    end
    for _, record in ipairs(Devices.list()) do
        local dx, dy = record.x - at:getX(), record.y - at:getY()
        if dx * dx + dy * dy <= Appliances.GREET_TILES * Appliances.GREET_TILES then
            local object = Devices.at(record.x, record.y, record.z, record.fullType)
            if object then
                sendServerCommand(player, Sync.MODULE, Devices.STATE, Devices.stateArgs(object))
            end
        end
    end
end

return Appliances
