-- Wires the game to the room simulation (Climate) and the devices (Appliances): world data at load, the minute
-- clock and the tick watch, players' device commands, and on a dedicated server the samples sent to each player and
-- the heat sources (the bridge and the heaters') the server needs, since it works out each player's body warmth from
-- its own air. Runs in single player and on a dedicated server; an MP client loads this file too and stops at the
-- first line. In single player the client side places the heat sources.

if isClient() then
    return
end

local Store = require("IndoorClimateRedone/Store")
local Sync = require("IndoorClimateRedone/Sync")
local Api = require("IndoorClimateRedone/Game/Api")
local Devices = require("IndoorClimateRedone/Game/Devices")
local Climate = require("IndoorClimateRedone/Climate")
local Sender = require("IndoorClimateRedone/Sender")
local Appliances = require("IndoorClimateRedone/Appliances")
local Bridge = require("IndoorClimateRedone/Game/Bridge")
local DeviceHeat = require("IndoorClimateRedone/Game/DeviceHeat")

local function worldHours()
    return getGameTime():getWorldAgeHours()
end

-- The public API reads the simulation here (and in single player, on the player's side too).
Api.provide({ sample = Climate.sample, room = Climate.roomAt })
-- In single player the device menu hands its commands straight to the server side.
Devices.serve(Appliances.command)

local function squaresOf(players)
    local squares = {}
    for _, player in ipairs(players) do
        local square = player:getCurrentSquare()
        if square then
            squares[#squares + 1] = square
        end
    end
    return squares
end

-- Dedicated server: sends the samples that are due and keeps the heat sources in step with the players.
local function flush(everyMinute)
    if not isServer() then
        return
    end
    local players = Climate.players()
    Sender.flush(players, Climate.sample, getTimestampMs())
    local settings = Climate.config()
    local active = Climate.active()
    for _, player in ipairs(players) do
        Bridge.follow(player, active and Climate.sample(player) or nil, settings)
    end
    Bridge.prune(players)
    if everyMinute or DeviceHeat.changed() then
        DeviceHeat.refresh(squaresOf(players))
    end
end

Events.OnInitGlobalModData.Add(function()
    Climate.start(ModData.getOrCreate(Store.KEY), worldHours())
    Sender.reset()
    Bridge.clear()
    DeviceHeat.clear()
    Appliances.start(Climate.reheat)
end)

Events.EveryOneMinute.Add(function()
    local nowHours = worldHours()
    Climate.update(nowHours)
    Appliances.update(nowHours, Climate.config())
    flush(true)
end)

Events.OnTick.Add(function()
    Climate.watch(worldHours())
    flush()
end)

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= Sync.MODULE or not player then
        return
    end
    if command == Sync.HELLO then
        Sender.greet(player, Climate.sample(player), getTimestampMs())
        Appliances.greet(player)
    elseif command == Devices.SWITCH or command == Devices.TANK then
        Appliances.command(player, command, args)
    end
end)

Events.LoadGridsquare.Add(Appliances.see)

Events.OnObjectAdded.Add(function(object)
    if Devices.isDevice(object) then
        Appliances.see(object:getSquare())
    end
end)

Events.OnObjectAboutToBeRemoved.Add(Appliances.removed)
