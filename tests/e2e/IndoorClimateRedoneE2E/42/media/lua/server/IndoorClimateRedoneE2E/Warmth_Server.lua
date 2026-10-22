-- Body warmth in multiplayer. The game works it out on the server from the server's own air (the client's core
-- temperature follows the server's), so the mod places its heat sources (the bridge and the heaters') on the server
-- as well as on the clients. This checks that the server's air near a heater matches the client's.
-- The outdoor air is held at -15 C (the admin climate override) and the player stands outdoors, where the game does
-- not hold the air at an indoor 22 C, with a propane heater on their square. For two game hours both sides log the outdoor air, the game's air for the character, the air their
-- thermoregulator works with and the core temperature. Runs last: it changes the weather and moves the player, and
-- puts both back.
if not isServer() then return end
require "PZE2E/PZE2E"

local Devices = require("IndoorClimateRedone/Game/Devices")
local Heater = require("IndoorClimateRedone/Heater")
local Climate = require("IndoorClimateRedone/Climate")

local COLD_C = -15
local READINGS = 12

local function temperatureFloat()
    return getClimateManager():getClimateFloat(ClimateManager.FLOAT_TEMPERATURE)
end

-- A free outdoor square on the ground floor within 15 tiles of the player, nearest first, or nil.
local function outdoorSquare(player)
    local cell = getCell()
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    for r = 2, 15 do
        for x = px - r, px + r do
            for y = py - r, py + r do
                if math.abs(x - px) == r or math.abs(y - py) == r then
                    local sq = cell:getGridSquare(x, y, 0)
                    if sq and not sq:isInARoom() and sq:isOutside() and sq:isFree(false) then
                        return sq
                    end
                end
            end
        end
    end
    return nil
end

local function reading(player)
    local climate = getClimateManager()
    local thermo = player:getBodyDamage():getThermoregulator()
    local s = Climate.sample(player)
    return {
        outdoorC = climate:getTemperature(),
        characterAirC = climate:getAirTemperatureForCharacter(player, false),
        thermoAirC = thermo:getTemperatureAir(),
        coreC = thermo:getCoreTemperature(),
        roomAirC = s and s.airC or nil,
    }
end

PZE2E.test("body warmth: the server's air or the client's", {
    function(ctx)
        local start = ctx.player:getCurrentSquare()
        local outside = outdoorSquare(ctx.player)
        PZE2E.check(outside ~= nil, "a free outdoor square near the player")
        if not outside then return end
        ctx.state.start = { x = start:getX(), y = start:getY(), z = start:getZ() }
        ctx.state.outside = outside
        local float = temperatureFloat()
        float:setEnableAdmin(true)
        float:setAdminValue(COLD_C)
        PZE2E.ask(ctx.player, "icrTeleport", { x = outside:getX(), y = outside:getY(), z = 0 }, "out")
    end,
    function(ctx)
        if not ctx.state.outside then return end
        if ctx.player:getCurrentSquare() ~= ctx.state.outside then return "wait" end
        local square = ctx.state.outside
        local item = instanceItem(Heater.PROPANE)
        item:getModData().ICLPropaneTankPresent = true
        item:getModData().ICLPropaneFuel = 1.0
        square:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
        ctx.state.object = Devices.on(square, Heater.PROPANE)
        ctx.state.args = { x = square:getX(), y = square:getY(), z = square:getZ(), fullType = Heater.PROPANE,
            active = true }
        ctx.state.readings = 0
        PZE2E.log("outdoor air held at %d C, the player outdoors at %d,%d with a propane heater", COLD_C,
            square:getX(), square:getY())
    end,
    function(ctx)
        if not ctx.state.object then return end
        if getClimateManager():getTemperature() > COLD_C + 1 then return "wait" end
        PZE2E.ask(ctx.player, "icrDeviceRequest", { command = Devices.SWITCH, args = ctx.state.args }, "on")
    end,
    function(ctx)
        if not ctx.state.object then return end
        if not ctx.answers.on then return "wait" end
        PZE2E.check(Devices.isOn(ctx.state.object), "the heater is on")
    end,
    function(ctx)
        if not ctx.state.object then return end
        ctx.state.readings = ctx.state.readings + 1
        local key = "reading" .. ctx.state.readings
        ctx.state[key] = reading(ctx.player)
        PZE2E.ask(ctx.player, "icrWarmth", {}, key)
        if ctx.state.readings < READINGS then return "wait" end
    end,
    function(ctx)
        if not ctx.state.object then
            temperatureFloat():setEnableAdmin(false)
            return
        end
        local last = "reading" .. READINGS
        if not ctx.answers[last] then return "wait" end
        for i = 1, READINGS do
            local s, c = ctx.state["reading" .. i], ctx.answers["reading" .. i]
            if s and c then
                PZE2E.log("warmth %2d: outdoor server %.1f client %.1f | character air server %.1f client %.1f | "
                    .. "thermoregulator air server %.1f client %.1f | core server %.2f client %.2f | room %s",
                    i, s.outdoorC, c.outdoorC or -999, s.characterAirC, c.characterAirC or -999, s.thermoAirC,
                    c.thermoAirC or -999, s.coreC, c.coreC or -999, tostring(c.roomAirC))
            end
        end
        local s, c = ctx.state[last], ctx.answers[last]
        local first = ctx.state.reading1
        PZE2E.log("verdict: character air server %.1f C, client %.1f C; thermoregulator air server %.1f C, client "
            .. "%.1f C; core over the run server %.2f -> %.2f C, client %.2f -> %.2f C", s.characterAirC,
            c.characterAirC or -999, s.thermoAirC, c.thermoAirC or -999, first.coreC, s.coreC,
            ctx.answers.reading1 and ctx.answers.reading1.coreC or -999, c.coreC or -999)
        PZE2E.check(s.characterAirC > COLD_C + 5, "the heater warms the server's air at the player (%.1f C)",
            s.characterAirC)
        PZE2E.check(c.characterAirC ~= nil and math.abs(c.characterAirC - s.characterAirC) < 1,
            "server and client agree on the air at the player (client %s C, server %.1f C)",
            tostring(c.characterAirC), s.characterAirC)
        PZE2E.check(math.abs(s.thermoAirC - s.characterAirC) < 1,
            "the server's thermoregulator works with that air (%.1f C)", s.thermoAirC)
        PZE2E.check(c.outdoorC ~= nil and c.outdoorC <= COLD_C + 1, "the client has the cold air too (%s C)",
            tostring(c.outdoorC))
        local float = temperatureFloat()
        float:setEnableAdmin(false)
        local args = ctx.state.args
        args.active = false
        Devices.request(ctx.player, Devices.SWITCH, args)
        ctx.state.object:getSquare():transmitRemoveItemFromSquare(ctx.state.object)
        PZE2E.ask(ctx.player, "icrTeleport", ctx.state.start, "back")
    end,
}, { startAfter = 1, every = 10, maxWaits = READINGS + 5 })
