-- The propane heater's tank, kept in the heater item's mod data under the original mod's field names, so heaters in
-- existing saves keep their tank. Fuel is the tank's fill, 0 to 1, as on a vanilla propane tank item.
--
-- Pure: works on the mod data table.
--
--   Propane.state(modData)                           present, fuel
--   Propane.set(modData, present, fuel)
--   Propane.hasFuel(modData)
--   Propane.burn(modData, profile, hours)            hasFuel, remaining, changed
--   Propane.percent(fuel)                            whole percent, as the menu shows it

local Config = require("IndoorClimateRedone/Config")

local Propane = {}

Propane.TANK_TYPE = "Base.PropaneTank"
-- A tank with no more than this is empty.
Propane.EMPTY = 0.000001
Propane.DEFAULT_USE_PER_HOUR = 0.025

function Propane.state(modData)
    if not modData or modData.ICLPropaneTankPresent ~= true then
        return false, 0
    end
    return true, Config.clamp(modData.ICLPropaneFuel, 0, 1)
end

function Propane.set(modData, present, fuel)
    if present then
        modData.ICLPropaneTankPresent = true
        modData.ICLPropaneFuel = Config.clamp(fuel, 0, 1)
    else
        modData.ICLPropaneTankPresent = nil
        modData.ICLPropaneFuel = nil
    end
end

function Propane.hasFuel(modData)
    local present, fuel = Propane.state(modData)
    return present and fuel > Propane.EMPTY
end

function Propane.usePerHour(profile)
    return math.max(0, tonumber(profile and profile.propaneUsePerHour) or Propane.DEFAULT_USE_PER_HOUR)
end

-- Burns `hours` of propane. Returns whether any is left, how much, and whether the fill changed.
function Propane.burn(modData, profile, hours)
    local present, fuel = Propane.state(modData)
    if not present then
        return false, 0, false
    end
    local remaining = Config.clamp(fuel - Propane.usePerHour(profile) * math.max(0, tonumber(hours) or 0), 0, 1)
    Propane.set(modData, true, remaining)
    return remaining > Propane.EMPTY, remaining, remaining ~= fuel
end

function Propane.percent(fuel)
    return math.floor((tonumber(fuel) or 0) * 100 + 0.5)
end

return Propane
