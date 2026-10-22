-- Devices on a dedicated server: a client switches a propane heater on and off through the same path as its context
-- menu, the server and the client agree on its state, the tank burns and the client hears about it; the electric
-- heater's menu on the client; the items, models and loot lists are loaded; Lua Digital Watch UI shows the room air.
if not isServer() then return end
require "PZE2E/PZE2E"

local Devices = require("IndoorClimateRedone/Game/Devices")
local Heater = require("IndoorClimateRedone/Heater")
local Climate = require("IndoorClimateRedone/Climate")

-- Puts a device on the ground on the player's square and returns its object and command arguments.
local function place(player, fullType, tank)
    local square = player:getCurrentSquare()
    local item = instanceItem(fullType)
    if tank then
        item:getModData().ICLPropaneTankPresent = true
        item:getModData().ICLPropaneFuel = tank
    end
    square:AddWorldInventoryItem(item, 0.5, 0.5, 0, true)
    local object = Devices.on(square, fullType)
    return object, { x = square:getX(), y = square:getY(), z = square:getZ(), fullType = fullType }
end

local function remove(object)
    if object and object:getSquare() then
        object:getSquare():transmitRemoveItemFromSquare(object)
    end
end

PZE2E.test("a client switches a propane heater and both sides agree", {
    function(ctx)
        if not Climate.sample(ctx.player) then return "wait" end
        local object, args = place(ctx.player, Heater.PROPANE, 1.0)
        PZE2E.check(object ~= nil, "propane heater placed at %d,%d,%d", args.x, args.y, args.z)
        ctx.state.object, ctx.state.args = object, args
        ctx.state.key = Devices.key(args.x, args.y, args.z, args.fullType)
        PZE2E.ask(ctx.player, "icrDevice", args, "placed")
    end,
    function(ctx)
        local c = ctx.answers.placed
        if not c then return "wait" end
        PZE2E.check(c.found == true, "the client sees the placed heater")
        -- Whether item mod data set before placing reaches the client with the item.
        PZE2E.log("client sees tank present=%s fuel=%s with the placed item", tostring(c.tankPresent),
            tostring(c.tankFuel))
        local args = {}
        for k, v in pairs(ctx.state.args) do args[k] = v end
        args.active = true
        PZE2E.ask(ctx.player, "icrDeviceRequest", { command = Devices.SWITCH, args = args }, "switchOn")
    end,
    function(ctx)
        if not ctx.answers.switchOn then return "wait" end
        local object = ctx.state.object
        PZE2E.check(Devices.isOn(object), "the server switched it on")
        PZE2E.check(Devices.get(ctx.state.key) ~= nil, "the server lists it as on")
        local s = Climate.sample(ctx.player)
        PZE2E.log("server sample %s", PZE2E.describe(s))
        PZE2E.check(s ~= nil and (s.heaterCount or 0) >= 1, "the player's sample counts %s device(s)",
            tostring(s and s.heaterCount))
        if s and s.baseRoomC < 24 then
            PZE2E.check(s.airC > s.baseRoomC, "the heater warms the sample: air %.2f C, room %.2f C", s.airC,
                s.baseRoomC)
        end
        PZE2E.ask(ctx.player, "icrDevice", ctx.state.args, "on")
    end,
    function(ctx)
        local c = ctx.answers.on
        if not c then return "wait" end
        PZE2E.log("client %s", PZE2E.describe(c))
        PZE2E.check(c.active == true, "the client sees it on")
        PZE2E.check(c.listed == true, "the client lists it as on")
        PZE2E.check(c.heatSource == true, "the client placed its heat source")
        PZE2E.check((c.heaterCount or 0) >= 1, "the client's sample counts %s device(s)", tostring(c.heaterCount))
        local sq = ctx.state.object:getSquare()
        PZE2E.log("game air at the heater: client %.2f C (vanilla read %.2f C), server %.2f C", c.squareAirC or -999,
            c.vanillaAirC or -999, getClimateManager():getAirTemperatureForSquare(sq))
    end,
    function(ctx)
        -- One percent of a tank burns in 24 game minutes.
        local _, fuel = require("IndoorClimateRedone/Propane").state(Devices.modData(ctx.state.object))
        if fuel > 0.985 then return "wait" end
        PZE2E.check(Devices.isOn(ctx.state.object), "still on with %.3f of a tank", fuel)
        ctx.state.fuel = fuel
        PZE2E.ask(ctx.player, "icrDevice", ctx.state.args, "burned")
    end,
    function(ctx)
        local c = ctx.answers.burned
        if not c then return "wait" end
        PZE2E.check(c.tankFuel ~= nil and c.tankFuel < 0.995 and math.abs(c.tankFuel - ctx.state.fuel) <= 0.011,
            "the client hears the tank go down: client %s, server %.3f", tostring(c.tankFuel), ctx.state.fuel)
        local args = {}
        for k, v in pairs(ctx.state.args) do args[k] = v end
        args.active = false
        PZE2E.ask(ctx.player, "icrDeviceRequest", { command = Devices.SWITCH, args = args }, "switchOff")
    end,
    function(ctx)
        if not ctx.answers.switchOff then return "wait" end
        PZE2E.check(not Devices.isOn(ctx.state.object), "the server switched it off")
        PZE2E.check(Devices.get(ctx.state.key) == nil, "the server no longer lists it")
        PZE2E.ask(ctx.player, "icrDevice", ctx.state.args, "off")
    end,
    function(ctx)
        local c = ctx.answers.off
        if not c then return "wait" end
        PZE2E.check(c.active == false and c.listed == false and c.heatSource == false,
            "the client sees it off, unlisted, without a heat source")
        remove(ctx.state.object)
    end,
}, { startAfter = 2, every = 1, maxWaits = 40 })

PZE2E.test("the electric heater's menu on the client follows the power", {
    function(ctx)
        local object, args = place(ctx.player, Heater.STANDARD)
        ctx.state.object, ctx.state.args = object, args
        ctx.state.powered = Devices.canRun(object)
        PZE2E.log("electric heater at %d,%d,%d, can run: %s", args.x, args.y, args.z, tostring(ctx.state.powered))
        PZE2E.ask(ctx.player, "icrMenu", args, "menu")
    end,
    function(ctx)
        local c = ctx.answers.menu
        if not c then return "wait" end
        PZE2E.log("client menu %s", PZE2E.describe(c))
        PZE2E.check(c.error == nil, "the menu builds on the client: %s", tostring(c.error))
        PZE2E.check(c.names == "Turn On Heater", "it offers %s", tostring(c.names))
        PZE2E.check(c.unavailable == not ctx.state.powered, "greyed out: %s, server can run it: %s",
            tostring(c.unavailable), tostring(ctx.state.powered))
        remove(ctx.state.object)
    end,
}, { startAfter = 1, every = 1, maxWaits = 10 })

PZE2E.test("the device items and loot lists are loaded", {
    function(ctx)
        local manager = getScriptManager()
        for fullType in pairs(Heater.PROFILES) do
            PZE2E.check(manager:getItem(fullType) ~= nil, "server knows %s", fullType)
        end
        local items = ProceduralDistributions.list.ElectronicStoreAppliances.items
        local weight = nil
        for i = 1, #items, 2 do
            if items[i] == Heater.STANDARD then weight = items[i + 1] end
        end
        PZE2E.check(weight == 18, "the cheap heater is in ElectronicStoreAppliances with weight %s", tostring(weight))
        PZE2E.ask(ctx.player, "icrItems", {}, "client")
    end,
    function(ctx)
        local c = ctx.answers.client
        if not c then return "wait" end
        PZE2E.check(c.items == 4, "the client knows %s device items", tostring(c.items))
        PZE2E.check(c.icons == 4, "the client finds %s device icons (%s)", tostring(c.icons), tostring(c.iconNames))
        PZE2E.check(c.models == 4, "the client finds %s device models", tostring(c.models))
    end,
}, { startAfter = 1, every = 1, maxWaits = 10 })

PZE2E.test("Lua Digital Watch UI shows the room air", {
    function(ctx)
        PZE2E.ask(ctx.player, "icrWatch", {}, "watch")
    end,
    function(ctx)
        local c = ctx.answers.watch
        if not c then return "wait" end
        if not c.present then
            PZE2E.log("Lua Digital Watch UI is not enabled on this bench: nothing to check")
            return
        end
        PZE2E.log("watch %s", PZE2E.describe(c))
        PZE2E.check(c.sampleAirC ~= nil, "the player is in a simulated room")
        PZE2E.check(c.resolved ~= nil and math.abs(c.resolved - (c.sampleAirC or -999)) < 0.01,
            "the watch's reader gives %s, the room is %s", tostring(c.resolved), tostring(c.sampleAirC))
        PZE2E.check(c.override ~= nil and math.abs(c.override - (c.sampleAirC or -999)) < 0.5,
            "the watch's override is %s", tostring(c.override))
    end,
}, { startAfter = 1, every = 1, maxWaits = 10 })
