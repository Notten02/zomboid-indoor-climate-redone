-- The generator info window lists the mod's electric devices a running generator powers, as in the original: one
-- line per device type ("Cheap Heater x2 (0.080 L/h)") above the generator's own line, and their draw added to the
-- total. A device counts for the generator it draws on (Devices.poweringGenerator) while the grid is off.
--
--   GeneratorInfo.load(generator, config)   { count, totalLph, entries = { { fullType, label, count, lphTotal } } }
--   GeneratorInfo.install()                 wraps ISGeneratorInfoWindow.getRichText once

local Heater = require("IndoorClimateRedone/Heater")
local Devices = require("IndoorClimateRedone/Game/Devices")
local Power = require("IndoorClimateRedone/Game/Power")

local GeneratorInfo = {}

-- The load is worked out again at most once a real second, or when a device changed state.
GeneratorInfo.CACHE_MS = 1000

-- generator -> { atMs, version, load }
local cache = {}

local function empty()
    return { count = 0, totalLph = 0, entries = {} }
end

local function scan(generator, config)
    if Power.grid() or not generator:isActivated() or not generator:isConnected() then
        return empty()
    end
    local at = generator:getSquare()
    if not at then
        return empty()
    end
    local radius = Devices.GENERATOR_RADIUS
    local byType, count, total = {}, 0, 0
    for _, record in ipairs(Devices.list()) do
        local profile = Heater.profile(record.fullType)
        local dx, dy = record.x - at:getX(), record.y - at:getY()
        if profile and not Heater.usesPropane(profile) and math.abs(record.z - at:getZ()) <= Devices.GENERATOR_FLOORS
            and dx * dx + dy * dy <= radius * radius then
            local object, square = Devices.at(record.x, record.y, record.z, record.fullType)
            if object and Devices.hasElectricity(square) and Devices.poweringGenerator(square, record) == generator then
                local rate = Heater.generatorFuelPerHour(profile, config)
                local entry = byType[record.fullType]
                if not entry then
                    entry = { fullType = record.fullType, label = object:getItem():getDisplayName() or profile.label,
                        count = 0, lphTotal = 0 }
                    byType[record.fullType] = entry
                end
                entry.count = entry.count + 1
                entry.lphTotal = entry.lphTotal + rate
                count = count + 1
                total = total + rate
            end
        end
    end
    local entries = {}
    for _, entry in pairs(byType) do
        entries[#entries + 1] = entry
    end
    table.sort(entries, function(a, b) return tostring(a.label) < tostring(b.label) end)
    return { count = count, totalLph = total, entries = entries }
end

function GeneratorInfo.load(generator, config)
    if not generator then
        return empty()
    end
    local nowMs = getTimestampMs()
    local cached = cache[generator]
    if cached and cached.version == Devices.version and nowMs - cached.atMs >= 0
        and nowMs - cached.atMs < GeneratorInfo.CACHE_MS then
        return cached.load
    end
    local load = scan(generator, config)
    cache[generator] = { atMs = nowMs, version = Devices.version, load = load }
    return load
end

local function replacePlain(text, target, replacement)
    local first, last = string.find(text, target, 1, true)
    if not first then
        return text, false
    end
    return string.sub(text, 1, first - 1) .. replacement .. string.sub(text, last + 1), true
end

-- "1,234 L/h" or "0.5 L/h" -> the number.
function GeneratorInfo.parseLph(value)
    local digits = type(value) == "string" and string.match(value, "(%d+[,%.]?%d*)") or nil
    return digits and tonumber((string.gsub(digits, ",", "."))) or nil
end

function GeneratorInfo.formatLph(value)
    return string.format("%.3f L/h", tonumber(value) or 0)
end

-- The window's text with the devices' lines and their draw in the total.
function GeneratorInfo.text(original, generator, config)
    local load = GeneratorInfo.load(generator, config)
    if load.totalLph <= 0 or #load.entries == 0 then
        return original
    end
    local lines = ""
    for _, entry in ipairs(load.entries) do
        lines = lines .. entry.label .. " x" .. tostring(entry.count) .. " (" .. GeneratorInfo.formatLph(entry.lphTotal)
            .. ") <LINE> "
    end
    local baseLine = getText("IGUI_Generator_TypeGas") .. " (" .. generator:getBasePowerConsumptionString()
        .. ") <LINE> "
    local text, inserted = replacePlain(original, baseLine, lines .. baseLine)
    local totalString = generator:getTotalPowerUsingString()
    local total = GeneratorInfo.parseLph(totalString)
    if total then
        text = replacePlain(text, getText("IGUI_Total") .. ": " .. totalString,
            getText("IGUI_Total") .. ": " .. GeneratorInfo.formatLph(total + load.totalLph))
    end
    if not inserted then
        text = text .. " <LINE> <INDENT:10> " .. lines
    end
    return text
end

local installed = false

-- `config()` returns the settings (Config.read).
function GeneratorInfo.install(config)
    if installed or not ISGeneratorInfoWindow or not ISGeneratorInfoWindow.getRichText then
        return
    end
    installed = true
    local original = ISGeneratorInfoWindow.getRichText
    ---@diagnostic disable-next-line: duplicate-set-field
    ISGeneratorInfoWindow.getRichText = function(object, displayStats)
        local text = original(object, displayStats)
        if not displayStats or not object or not object:isActivated() then
            return text
        end
        return GeneratorInfo.text(text, object, config())
    end
end

return GeneratorInfo
