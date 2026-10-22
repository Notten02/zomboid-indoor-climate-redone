-- Settings: the sandbox options (SandboxVars.IndoorClimateLite.*) and the fixed tuning values.
--
-- The option names, ranges and defaults are the original mod's, so existing server configs carry over.
-- media/sandbox-options.txt declares the same options; tests/config_spec.lua keeps the two in step.
-- Pure: the sandbox table is passed in.

local Config = {}

-- In the order of sandbox-options.txt. `round` options are integers in the game and rounded here.
Config.OPTIONS = {
    { name = "Enabled", type = "boolean", default = true },
    { name = "UpdateMinutes", type = "integer", min = 1, max = 60, default = 1, round = true },
    { name = "UnvisitedOffsetC", type = "double", min = 0.0, max = 10.0, default = 2.0 },
    { name = "HeaterGeneratorFuelPerHour", type = "double", min = 0.0, max = 0.25, default = 0.04 },
    { name = "PoweredTargetC", type = "double", min = 22.0, max = 27.0, default = 22.0 },
    { name = "PoweredRatePerHour", type = "double", min = 0.1, max = 10.0, default = 3.0 },
    { name = "PoweredLeakInfluence", type = "double", min = 0.0, max = 1.0, default = 0.75 },
    { name = "SealedLossPerHour", type = "double", min = 0.005, max = 0.5, default = 0.06 },
    { name = "BreachMultiplier", type = "double", min = 1.0, max = 30.0, default = 12.0 },
    { name = "ScanRadius", type = "integer", min = 2, max = 10, default = 5, round = true },
    { name = "NativeBridge", type = "boolean", default = true },
    { name = "DebugLogging", type = "boolean", default = false },
}

-- Tuning that is not a sandbox option.
Config.FIXED = {
    -- How fast an unpowered room warms toward vanilla air that is warmer than the room (sun, fire, heat sources).
    LocalHeatRatePerHour = 2.0,
    -- Longest gap one update catches up on; a room left alone for longer is stepped as if 168 hours had passed.
    MaxElapsedHours = 168.0,
    -- Squares one zone's envelope scan visits per update, and all scans together on one server.
    EnvelopeScanBudget = 300,
    ServerScanBudget = 1500,
    -- How old a finished scan may get before it is redone, and how soon a scan that hit unloaded map is retried.
    EnvelopeRefreshHours = 6.0,
    EnvelopeRetryHours = 0.25,
    -- Saved zone states kept in world data (the least recently seen go first), and envelope scans kept in memory
    -- for zones nobody is in.
    MaxStoredZones = 1024,
    MaxEnvelopeCaches = 24,
}

-- tonumber(value) held to [minimum, maximum]; anything that is not a number becomes minimum.
function Config.clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function readOption(source, option)
    local raw = source and source[option.name]
    if option.type == "boolean" then
        if raw ~= nil then
            return raw == true
        end
        return option.default
    end
    local value = Config.clamp(tonumber(raw) or option.default, option.min, option.max)
    if option.round then
        value = math.floor(value + 0.5)
    end
    return value
end

-- A full settings table from SandboxVars.IndoorClimateLite (may be nil): every option read and clamped to its range,
-- a missing or non-numeric value replaced by its default, plus the fixed values.
function Config.read(source)
    if type(source) ~= "table" then
        source = nil
    end
    local config = {}
    for _, option in ipairs(Config.OPTIONS) do
        config[option.name] = readOption(source, option)
    end
    for name, value in pairs(Config.FIXED) do
        config[name] = value
    end
    return config
end

-- The settings with every option at its default.
function Config.defaults()
    return Config.read(nil)
end

return Config
