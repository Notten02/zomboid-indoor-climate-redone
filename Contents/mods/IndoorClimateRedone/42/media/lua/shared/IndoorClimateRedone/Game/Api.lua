-- The public API: the global `IndoorClimateLite` table other mods read (Extensive Health Redone, Lua Digital Watch
-- UI). The name, the functions and the sample fields are the original mod's, so mods written for it keep working.
--
--   IndoorClimateLite.VERSION
--   IndoorClimateLite.isActive()                         simulation on and no conflicting mod
--   IndoorClimateLite.refreshConfig()                    re-reads the sandbox options, returns IndoorClimateLite.Config
--   IndoorClimateLite.getRoomDescriptor(square)          the room the square is in, or nil outdoors
--   IndoorClimateLite.isIndoorSquare(square)
--   IndoorClimateLite.getTemperatureSample(player)       a copy of the player's room sample (below)
--   IndoorClimateLite.getLiveTemperatureSample(player)   the sample itself, not copied (read only), or nil
--   IndoorClimateLite.getTemperatureForPlayer(player)    deg C
--   IndoorClimateLite.getTemperatureForSquare(square, player)   deg C
--
-- A sample: source = "IndoorClimateLite", version, active, airC, baseRoomC, targetC, outdoorC, vanillaAirC,
-- indoors, powered, roomKey, buildingKey, roomKind, roomArea, leakScore, openDoors, openWindows, heaterActive,
-- heaterCount, heaterDeltaC, heaterRadius, heaterLeakRetention, the envelope scan figures and the hour it was
-- stepped. airC is the room with the switched-on devices near the player (see Heater), baseRoomC the room alone.
-- Outside the simulated rooms the sample is the game's own air at the player, changed by devices near them
-- (indoors tells whether the square is in a room, roomKey is nil). getTemperatureForSquare applies the devices too.
--
-- The API works the same on a dedicated server, on its clients and in single player. Where the samples come from
-- is plugged in with Api.provide: the room simulation on a server and in single player, the samples the server sent
-- on a multiplayer client. A player defaults to the first local player. Never errors on a nil player or square.

local Config = require("IndoorClimateRedone/Config")
local Places = require("IndoorClimateRedone/Game/Places")
local Conflicts = require("IndoorClimateRedone/Game/Conflicts")
local Devices = require("IndoorClimateRedone/Game/Devices")

local Api = {}

Api.SOURCE = "IndoorClimateLite"
-- The mod version (mod.info modversion).
Api.VERSION = "0.1.0"

-- { sample = fn(player) -> sample or nil, room = fn(square, player) -> temperature, leakScore (or nil) }
local provider = nil

-- Plugs in where samples and room temperatures come from (nil unplugs).
function Api.provide(source)
    provider = source
end

-- The settings and the conflict check are read again at most once a real second: a UI may ask every frame.
Api.REFRESH_MS = 1000
local settings, conflict, readAtMs = nil, false, nil

local function refresh()
    settings = Config.read(SandboxVars and SandboxVars.IndoorClimateLite)
    conflict = Conflicts.active()
    readAtMs = getTimestampMs()
    return settings
end

local function config()
    if not settings or not readAtMs or math.abs(getTimestampMs() - readAtMs) >= Api.REFRESH_MS then
        refresh()
    end
    return settings
end

function Api.isActive()
    return config().Enabled == true and not conflict
end

-- The settings (Config.read), at most a second old.
function Api.config()
    return config()
end

local function owner(player)
    if player then
        return player
    end
    return getSpecificPlayer and getSpecificPlayer(0) or nil
end

local function outdoorAir()
    local climate = getClimateManager()
    return climate and tonumber(climate:getTemperature()) or 15.0
end

-- The game's own air at a square (the outdoor air without a square).
local function vanillaAir(square)
    local climate = getClimateManager()
    if climate and square then
        return tonumber(climate:getAirTemperatureForSquare(square)) or outdoorAir()
    end
    return outdoorAir()
end

local function gridPower()
    local world = getWorld and getWorld() or nil
    return world ~= nil and world:isHydroPowerOn() == true
end

-- The player's simulated room sample (the provider's table, not a copy), or nil.
function Api.liveSample(player)
    player = owner(player)
    if not player or not provider or not Api.isActive() then
        return nil
    end
    return provider.sample(player)
end

local function fallbackSample(player)
    local square = player and player:getCurrentSquare() or nil
    local air = vanillaAir(square)
    local airC, delta, count, radius = Devices.adjust(square, air, 0, config())
    return {
        source = Api.SOURCE,
        version = Api.VERSION,
        active = Api.isActive(),
        airC = airC,
        baseRoomC = air,
        outdoorC = outdoorAir(),
        vanillaAirC = air,
        indoors = square ~= nil and Places.describe(square) ~= nil,
        powered = gridPower(),
        heaterActive = count > 0,
        heaterCount = count,
        heaterDeltaC = delta,
        heaterRadius = radius,
    }
end

function Api.sample(player)
    player = owner(player)
    local live = Api.liveSample(player)
    if not live then
        return fallbackSample(player)
    end
    local copy = {}
    for name, value in pairs(live) do
        copy[name] = value
    end
    copy.source = Api.SOURCE
    copy.version = Api.VERSION
    copy.active = true
    return copy
end

function Api.temperatureForSquare(square, player)
    if not square then
        return outdoorAir()
    end
    player = owner(player)
    local temperature, leakScore = nil, 0
    if provider and Api.isActive() and Places.describe(square) then
        local room, leak = provider.room(square, player)
        if tonumber(room) then
            temperature, leakScore = tonumber(room), tonumber(leak) or 0
        end
    end
    return (Devices.adjust(square, temperature or vanillaAir(square), leakScore, config()))
end

function Api.temperatureForPlayer(player)
    if not player then
        return outdoorAir()
    end
    local live = Api.liveSample(player)
    if live and tonumber(live.airC) then
        return tonumber(live.airC)
    end
    return Api.temperatureForSquare(player:getCurrentSquare(), player)
end

-- Fills the global table. Other fields a mod put there are kept.
function Api.install()
    IndoorClimateLite = IndoorClimateLite or {}
    local icl = IndoorClimateLite
    icl.VERSION = Api.VERSION
    icl.Config = icl.Config or {}
    icl.refreshConfig = function()
        local fresh = refresh()
        for name in pairs(icl.Config) do
            icl.Config[name] = nil
        end
        for name, value in pairs(fresh) do
            icl.Config[name] = value
        end
        return icl.Config
    end
    icl.isActive = Api.isActive
    icl.getRoomDescriptor = Places.describe
    icl.isIndoorSquare = function(square)
        return Places.describe(square) ~= nil
    end
    icl.getTemperatureSample = Api.sample
    icl.getLiveTemperatureSample = Api.liveSample
    icl.getTemperatureForPlayer = Api.temperatureForPlayer
    icl.getTemperatureForSquare = Api.temperatureForSquare
    icl.refreshConfig()
    return icl
end

Api.install()

return Api
