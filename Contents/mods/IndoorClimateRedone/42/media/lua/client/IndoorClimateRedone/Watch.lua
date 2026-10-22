-- Lua Digital Watch UI shows the room air on the watch, as in the original: indoors in a simulated room the watch
-- reads the player's sample (airC), elsewhere what it read before (another mod's reader, or the game's air for the
-- character).
--
-- Two hooks, both kept up because other mods can replace them: the watch's temperature reader
-- (setTemperatureResolver; the one found there is kept as the fallback), and its temperature override, which the
-- watch prefers over any reader. The override is released only while it still holds the value set here, so another
-- mod's override is left alone. Unseasonal Weather's own clock (UW_DigitalWatchUI) gets the same reader on its
-- class, since it is created again after every sleep.
--
-- Installed at game start, not when this file loads, so the load order does not matter; checked again every game
-- minute, every REPAIR_TICKS player updates and whenever the watch resolves its state. A require that finds no watch
-- is not tried again: the game logs a warning for every failed require, and no mod is added during a game.
--
--   Watch.install()   hooks the watch and the Unseasonal Weather clock when they are there
--   Watch.temperature(player)   the room air the watch shows for the player, or nil

local Api = require("IndoorClimateRedone/Game/Api")

local Watch = {}

Watch.REPAIR_TICKS = 120
Watch.MODULE = "LuaDigitalWatch/LuaDigitalWatch"
local UW_MARKER = "_IndoorClimateRedonePatched"
local UW_ORIGINAL = "_IndoorClimateRedoneOriginal"

local installedResolver = nil
local fallbackResolver = nil
local watched = nil
local appliedOverride = nil
local countdown = 0
local watchMissing = false

function Watch.temperature(player)
    if not player or not Api.isActive() or player:getVehicle() then
        return nil
    end
    local sample = Api.liveSample(player) or Api.sample(player)
    if type(sample) ~= "table" or sample.active == false or sample.indoors ~= true then
        return nil
    end
    return tonumber(sample.airC)
end

local function vanilla(player, ui)
    if fallbackResolver then
        local ok, value = pcall(fallbackResolver, player, ui)
        if ok and tonumber(value) then
            return tonumber(value)
        end
    end
    local climate = getClimateManager()
    if player then
        return climate:getAirTemperatureForCharacter(player, false)
    end
    return climate:getTemperature()
end

local function resolve(player, ui)
    return Watch.temperature(player) or vanilla(player, ui)
end

local function patchUnseasonalWeather()
    local clock = rawget(_G, "UW_DigitalWatchUI")
    if type(clock) ~= "table" or type(clock.getDisplayTemperature) ~= "function" or clock[UW_MARKER] then
        return
    end
    local original = clock[UW_ORIGINAL] or clock.getDisplayTemperature
    clock[UW_ORIGINAL] = original
    clock.getDisplayTemperature = function(self)
        local player = self and self.clockPlayer or getSpecificPlayer(0)
        local temperature = Watch.temperature(player)
        if temperature ~= nil then
            return temperature
        end
        return original(self)
    end
    clock[UW_MARKER] = true
end

local function watchPlayer(api)
    if type(api.getInstance) == "function" then
        local instance = api.getInstance()
        if instance and instance.clockPlayer then
            return instance.clockPlayer
        end
    end
    return getSpecificPlayer(0)
end

local function setOverride(api, value)
    if value == nil and type(api.clearOverride) == "function" then
        return api.clearOverride("temperature")
    end
    if type(api.setOverride) == "function" then
        return api.setOverride("temperature", value)
    end
    return false
end

local function syncOverride(api)
    if type(api.getOverrides) ~= "function" then
        return
    end
    local overrides = api.getOverrides(api)
    if type(overrides) ~= "table" then
        return
    end
    local current = tonumber(overrides.temperature)
    local wanted = Watch.temperature(watchPlayer(api))
    if wanted ~= nil then
        if current == nil or math.abs(current - wanted) > 0.005 then
            if setOverride(api, wanted) then
                appliedOverride = wanted
            end
        else
            appliedOverride = wanted
        end
        return
    end
    -- Outdoors, in a vehicle or switched off: let go of our override only.
    if appliedOverride ~= nil and current ~= nil and math.abs(current - appliedOverride) <= 0.005 then
        setOverride(api, nil)
    end
    appliedOverride = nil
end

local function maintain(api)
    if not api then
        return
    end
    local current = api.getTemperatureResolver()
    if Api.isActive() and (installedResolver == nil or current ~= installedResolver) then
        if current ~= nil and current ~= resolve then
            fallbackResolver = current
        end
        installedResolver = resolve
        api.setTemperatureResolver(resolve)
    end
    syncOverride(api)
end

local function onStateResolved()
    maintain(watched)
end

local function loadWatch()
    if watchMissing then
        return nil
    end
    local ok, api = pcall(require, Watch.MODULE)
    if not ok or type(api) ~= "table" then
        watchMissing = true
        return nil
    end
    if type(api.setTemperatureResolver) ~= "function"
        or type(api.getTemperatureResolver) ~= "function" then
        return nil
    end
    return api
end

function Watch.install()
    patchUnseasonalWeather()
    local api = loadWatch()
    if not api then
        return false
    end
    if type(api.init) == "function" then
        api.init()
    end
    if watched ~= api then
        watched = api
        if type(api.on) == "function" then
            api.on("watch:state_resolved", onStateResolved)
        end
    end
    maintain(api)
    return true
end

-- Every player update of the first local player; installs again every REPAIR_TICKS of them.
function Watch.tick(player)
    if player and player:getPlayerNum() ~= 0 then
        return
    end
    if countdown > 0 then
        countdown = countdown - 1
        return
    end
    countdown = Watch.REPAIR_TICKS
    Watch.install()
end

function Watch.reset()
    countdown = 0
    watchMissing = false
end

return Watch
