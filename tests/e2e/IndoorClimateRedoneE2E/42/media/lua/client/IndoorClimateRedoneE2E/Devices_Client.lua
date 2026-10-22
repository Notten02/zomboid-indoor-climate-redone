-- Device tests, client side: what this client knows about a device, a device command sent the way the context menu
-- sends it, the context menu itself, the items and the watch.
require "PZE2E/PZE2E"

local Devices = require("IndoorClimateRedone/Game/Devices")
local HeatSources = require("IndoorClimateRedone/Game/HeatSources")
local Heater = require("IndoorClimateRedone/Heater")
local Propane = require("IndoorClimateRedone/Propane")

PZE2E.answer("icrDevice", function(args)
    local object, square = Devices.at(args.x, args.y, args.z, args.fullType)
    local modData = Devices.modData(object)
    local present, fuel = Propane.state(modData)
    local key = Devices.key(args.x, args.y, args.z, args.fullType)
    local s = IndoorClimateLite.getTemperatureSample(getPlayer())
    local climate = getClimateManager()
    return {
        found = object ~= nil,
        active = modData ~= nil and modData.ICLHeaterActive == true,
        tankPresent = present,
        tankFuel = present and fuel or nil,
        listed = Devices.get(key) ~= nil,
        heatSource = HeatSources.get("device:" .. key) ~= nil,
        heaterCount = s.heaterCount,
        airC = s.airC,
        baseRoomC = s.baseRoomC,
        squareAirC = square and climate:getAirTemperatureForSquare(square) or nil,
        vanillaAirC = square and HeatSources.without(function() return climate:getAirTemperatureForSquare(square) end)
            or nil,
    }
end)

PZE2E.answer("icrDeviceRequest", function(args)
    Devices.request(getPlayer(), args.command, args.args)
    return { sent = true }
end)

-- Builds the device's world context menu with a stand-in context and reports the options.
PZE2E.answer("icrMenu", function(args)
    local object = Devices.at(args.x, args.y, args.z, args.fullType)
    local options = {}
    local context = {}
    function context:addOption(name)
        local option = { name = name }
        options[#options + 1] = option
        return option
    end
    local ok, err = pcall(require("IndoorClimateRedone/DeviceMenu").world, 0, context, { object })
    local names, unavailable = {}, false
    for _, option in ipairs(options) do
        names[#names + 1] = option.name
        unavailable = unavailable or option.notAvailable == true
    end
    return { error = not ok and tostring(err) or nil, names = table.concat(names, ", "), unavailable = unavailable }
end)

PZE2E.answer("icrItems", function()
    local manager = getScriptManager()
    local items, icons, models, names = 0, 0, 0, {}
    for fullType in pairs(Heater.PROFILES) do
        local script = manager:getItem(fullType)
        if script then
            items = items + 1
            -- The texture the game resolved for the item's icon; a missing icon falls back to another texture.
            local texture = script:getNormalTexture()
            local name = texture and texture:getName() or "none"
            names[#names + 1] = name
            if string.find(name, script:getIcon(), 1, true) then icons = icons + 1 end
            if manager:getModelScript(script:getWorldStaticModel()) then models = models + 1 end
        end
    end
    return { items = items, icons = icons, models = models, iconNames = table.concat(names, ", ") }
end)

PZE2E.answer("icrWatch", function()
    local ok, Watch = pcall(require, "LuaDigitalWatch/LuaDigitalWatch")
    if not ok or type(Watch) ~= "table" or not Watch.getTemperatureResolver then
        return { present = false }
    end
    local player = getPlayer()
    local resolver = Watch.getTemperatureResolver()
    local live = IndoorClimateLite.getLiveTemperatureSample(player)
    return {
        present = true,
        sampleAirC = live and live.airC or nil,
        resolved = resolver and resolver(player, nil) or nil,
        override = Watch.getOverrides(Watch).temperature,
    }
end)
