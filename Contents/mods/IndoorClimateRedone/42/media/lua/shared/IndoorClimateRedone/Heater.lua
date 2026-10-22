-- The devices (three heaters and a fan) and how they change the air near them. The original mod's item types,
-- figures and rules.
--
-- A switched-on device changes the air on its own floor within its radius, falling off in a straight line from its
-- square (walls do not stop it). A "delta" device adds or takes away a fixed amount at its centre (the cheap heater
-- +12 C, the fan -10 C); "target" devices lift the air toward their target (25 C) by the gap to it, and only the
-- strongest lift counts. Delta devices add up to at most +16 C or -20 C. The whole change is then weakened by the
-- room's leaks: a room that leaks completely keeps 1 - PoweredLeakInfluence of it. The result changes the air a
-- player feels in the room (the sample's airC), not the room's own temperature.
--
-- Pure: devices are passed in as plain tables { x, y, z, fullType }.
--
--   Heater.profile(fullType)                                  the device's profile, or nil for any other item
--   Heater.delta(devices, x, y, z, baseC, leakScore, config)  delta C, devices in reach, largest radius, retention
--   Heater.adjust(devices, x, y, z, baseC, leakScore, config) the air with the devices' change, then the delta etc.

local Config = require("IndoorClimateRedone/Config")

local Heater = {}

Heater.STANDARD = "IndoorClimateLite.ElectricHeater"
Heater.PREMIUM = "IndoorClimateLite.PremiumHeater"
Heater.FAN = "IndoorClimateLite.StandingFan"
Heater.PROPANE = "IndoorClimateLite.PropaneHeater"

-- radius: tiles. sourceTemperature: the game heat source a heater places (nativeHeatSource false: none).
-- generatorFuelPerHour: a device's own generator draw (others use the HeaterGeneratorFuelPerHour option).
-- Text keys name the context-menu entries; the fallbacks are shown while no translation has the key.
Heater.PROFILES = {
    [Heater.STANDARD] = {
        fullType = Heater.STANDARD, radius = 6, sourceTemperature = 40, heatMode = "delta", centerDeltaC = 12,
        label = "Cheap Heater",
        installKey = "ContextMenu_ICLInstallHeater", installText = "Install Heater",
        turnOnKey = "ContextMenu_ICLTurnOnHeater", turnOnText = "Turn On Heater",
        turnOffKey = "ContextMenu_ICLTurnOffHeater", turnOffText = "Turn Off Heater",
    },
    [Heater.PREMIUM] = {
        fullType = Heater.PREMIUM, radius = 12, sourceTemperature = 25, heatMode = "target", targetC = 25,
        label = "Premium Heater",
        installKey = "ContextMenu_ICLInstallHeater", installText = "Install Heater",
        turnOnKey = "ContextMenu_ICLTurnOnHeater", turnOnText = "Turn On Heater",
        turnOffKey = "ContextMenu_ICLTurnOffHeater", turnOffText = "Turn Off Heater",
    },
    [Heater.FAN] = {
        fullType = Heater.FAN, radius = 8, nativeHeatSource = false, heatMode = "delta", centerDeltaC = -10,
        generatorFuelPerHour = 0.20,
        label = "Standing Fan",
        installKey = "ContextMenu_ICLInstallFan", installText = "Install Standing Fan",
        turnOnKey = "ContextMenu_ICLTurnOnFan", turnOnText = "Turn On Fan",
        turnOffKey = "ContextMenu_ICLTurnOffFan", turnOffText = "Turn Off Fan",
    },
    [Heater.PROPANE] = {
        fullType = Heater.PROPANE, radius = 10, sourceTemperature = 25, heatMode = "target", targetC = 25,
        fuel = "propane", propaneUsePerHour = 0.025,
        label = "Propane Heater",
        installKey = "ContextMenu_ICLInstallPropaneHeater", installText = "Install Propane Heater",
        turnOnKey = "ContextMenu_ICLTurnOnPropaneHeater", turnOnText = "Turn On Propane Heater",
        turnOffKey = "ContextMenu_ICLTurnOffPropaneHeater", turnOffText = "Turn Off Propane Heater",
    },
}

-- The largest device radius.
Heater.MAX_RADIUS = 12
-- Bounds on the sum of the delta devices.
Heater.MAX_COMBINED_DELTA_C = 16
Heater.MAX_COMBINED_COOLING_C = 20
-- The air a device changes stays within these.
Heater.MIN_AIR_C = -80
Heater.MAX_AIR_C = 45

function Heater.profile(fullType)
    return fullType and Heater.PROFILES[fullType] or nil
end

-- True for a device that burns propane rather than using electricity.
function Heater.usesPropane(profile)
    return profile ~= nil and profile.fuel == "propane"
end

-- Litres of generator fuel an hour for an electric device.
function Heater.generatorFuelPerHour(profile, config)
    local own = profile and tonumber(profile.generatorFuelPerHour)
    if own then
        return math.max(0, own)
    end
    return math.max(0, tonumber(config.HeaterGeneratorFuelPerHour) or 0)
end

-- The share of a device's change a room with this leak score keeps.
function Heater.retention(leakScore, config)
    local leak = Config.clamp(leakScore, 0, 1)
    return 1.0 - leak * Config.clamp(config.PoweredLeakInfluence, 0, 1)
end

function Heater.delta(devices, x, y, z, baseC, leakScore, config)
    local base = tonumber(baseC) or 15
    local additive, lift, count, maxRadius = 0, 0, 0, 0
    for _, device in ipairs(devices) do
        local profile = Heater.profile(device.fullType)
        if profile and device.z == z then
            local dx, dy = x - device.x, y - device.y
            local distanceSquared = dx * dx + dy * dy
            if distanceSquared < profile.radius * profile.radius then
                local influence = 1.0 - math.sqrt(distanceSquared) / profile.radius
                if profile.heatMode == "target" then
                    lift = math.max(lift, math.max(0, profile.targetC - base) * influence)
                else
                    additive = additive + profile.centerDeltaC * influence
                end
                count = count + 1
                maxRadius = math.max(maxRadius, profile.radius)
            end
        end
    end
    local retention = Heater.retention(leakScore, config)
    additive = Config.clamp(additive, -Heater.MAX_COMBINED_COOLING_C, Heater.MAX_COMBINED_DELTA_C)
    return (lift + additive) * retention, count, maxRadius, retention
end

function Heater.adjust(devices, x, y, z, baseC, leakScore, config)
    local base = tonumber(baseC) or 15
    local delta, count, radius, retention = Heater.delta(devices, x, y, z, base, leakScore, config)
    return Config.clamp(base + delta, Heater.MIN_AIR_C, Heater.MAX_AIR_C), delta, count, radius, retention
end

return Heater
