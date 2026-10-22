-- Wires the player's side: on a multiplayer client the samples and device states the server sends feed the public
-- API and the device list, and in single player and multiplayer alike each local player's bridge heat source
-- (Game/Bridge) follows their sample, switched-on heaters place their heat sources (Game/DeviceHeat), and the device
-- context menus (DeviceMenu), the generator info window (GeneratorInfo) and Lua Digital Watch UI (Watch) are hooked in.

local Api = require("IndoorClimateRedone/Game/Api")
local Sync = require("IndoorClimateRedone/Sync")
local Devices = require("IndoorClimateRedone/Game/Devices")
local HeatSources = require("IndoorClimateRedone/Game/HeatSources")
local Samples = require("IndoorClimateRedone/Samples")
local Bridge = require("IndoorClimateRedone/Game/Bridge")
local DeviceHeat = require("IndoorClimateRedone/Game/DeviceHeat")
local DeviceMenu = require("IndoorClimateRedone/DeviceMenu")
local GeneratorInfo = require("IndoorClimateRedone/GeneratorInfo")
local Watch = require("IndoorClimateRedone/Watch")

if isClient() then
    Api.provide({ sample = Samples.of, room = Samples.roomAt })
end

-- The squares the local players stand on.
local function localSquares()
    local squares = {}
    for index = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(index)
        local square = player and player:getCurrentSquare() or nil
        if square then
            squares[#squares + 1] = square
        end
    end
    return squares
end

local function clearAll()
    Samples.clear()
    DeviceHeat.clear()
    Bridge.clear()
    HeatSources.clear()
    if isClient() then
        Devices.clear()
    end
    Watch.reset()
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= Sync.MODULE then
        return
    end
    if command == Devices.STATE then
        if DeviceHeat.receive(args) then
            DeviceHeat.refresh(localSquares())
        end
    else
        Samples.receive(command, args)
    end
end)

Events.OnCreatePlayer.Add(function(_, player)
    if isClient() and player then
        Samples.hello(player)
    end
end)

-- Every tick for each local player; the bridge is only touched when the sample, the square or the vehicle changed.
Events.OnPlayerUpdate.Add(function(player)
    if not player or not player:isLocalPlayer() then
        return
    end
    Watch.tick(player)
    Bridge.follow(player, Api.liveSample(player), Api.config())
end)

Events.OnTick.Add(function()
    if DeviceHeat.changed() then
        DeviceHeat.refresh(localSquares())
    end
end)

Events.EveryOneMinute.Add(function()
    local squares = localSquares()
    if isClient() then
        DeviceHeat.look(squares)
    end
    DeviceHeat.refresh(squares)
    Watch.install()
end)

Events.OnGameStart.Add(function()
    GeneratorInfo.install(Api.config)
    Watch.install()
    DeviceHeat.refresh(localSquares())
end)

Events.OnCreateUI.Add(Watch.install)

Events.OnPreFillInventoryObjectContextMenu.Add(DeviceMenu.inventory)
Events.OnPreFillWorldObjectContextMenu.Add(DeviceMenu.world)

-- On a multiplayer client, the squares it loads tell it which devices are on; on a server they are the server's.
if isClient() then
    Events.LoadGridsquare.Add(Devices.see)
    Events.OnObjectAdded.Add(function(object)
        if Devices.isDevice(object) then
            Devices.see(object:getSquare())
        end
    end)
    Events.OnObjectAboutToBeRemoved.Add(function(object)
        if Devices.isDevice(object) and object:getSquare() then
            Devices.forget(Devices.keyOf(object))
        end
    end)
end

Events.OnDisconnect.Add(clearAll)
Events.OnMainMenuEnter.Add(clearAll)
