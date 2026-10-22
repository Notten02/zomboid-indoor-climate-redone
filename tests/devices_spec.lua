-- LuaLS's bundled luassert definitions omit the optional failure-message argument; the UI stand-ins are partial.
---@diagnostic disable: redundant-parameter, missing-fields
-- The devices in a running game: switching them on the server, fuel, propane tanks, generators and switching off,
-- finding them, what clients learn, the heat sources heaters place, the context menus, the public API and the
-- generator info window.
local House = require("support/house")
local Sync = require("IndoorClimateRedone/Sync")
local Heater = require("IndoorClimateRedone/Heater")

local STANDARD, PREMIUM, FAN, PROPANE = Heater.STANDARD, Heater.PREMIUM, Heater.FAN, Heater.PROPANE

local function args(object, extra)
    local square = object:getSquare()
    local result = { x = square:getX(), y = square:getY(), z = square:getZ(), fullType = object:getItem():getFullType() }
    for name, value in pairs(extra or {}) do
        result[name] = value
    end
    return result
end

local function command(game, player, name, object, extra)
    game.events.OnClientCommand.trigger(Sync.MODULE, name, player, args(object, extra))
end

local function switch(game, player, object, on)
    command(game, player, "device_switch", object, { active = on })
end

local function broadcasts(game)
    local found = {}
    for _, message in ipairs(game.sent) do
        if message.player == nil and message.command == "device_state" then
            found[#found + 1] = message.args
        end
    end
    return found
end

local function isOn(object)
    return object:getItem():getModData().ICLHeaterActive == true
end

insulate("devices on the server", function()
    it("switch on for a player in reach with electricity, and everyone is told", function()
        local game, world, _, Climate = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        assert.is_true(isOn(heater))
        assert.are.equal(game.minutes / 60, heater:getItem():getModData().ICLHeaterFuelHour)
        assert.are.equal("11:12:0", heater:getItem():getModData().ICLDeviceAt)
        local sent = broadcasts(game)
        assert.are.equal(1, #sent)
        assert.are.same({ x = 11, y = 12, z = 0, fullType = STANDARD, active = true,
            fuelHour = game.minutes / 60, tankPresent = false, tankFuel = 0 }, sent[1])
        -- The player's sample takes the heater in at once: one tile away, 12 * (1 - 1/6).
        local sample = assert(Climate).sample(player)
        assert.are.equal(1, sample.heaterCount)
        assert.is_true(sample.heaterActive)
        assert.near(10, sample.heaterDeltaC, 1e-9)
        assert.near(sample.baseRoomC + 10, sample.airC, 1e-9)

        switch(game, player, heater, false)
        assert.is_false(isOn(heater))
        assert.is_nil(heater:getItem():getModData().ICLHeaterFuelHour)
        assert.are.equal(2, #broadcasts(game))
        sample = Climate.sample(player)
        assert.are.equal(0, sample.heaterCount)
        assert.are.equal(sample.baseRoomC, sample.airC)
    end)

    it("refuse a player out of reach or on another floor, a device without power, and malformed commands", function()
        local game, world = House.setup({ power = false })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        assert.is_false(isOn(heater))
        game.power = true
        local far = world:device(15, 13, 0, STANDARD)
        switch(game, player, far, true)
        assert.is_false(isOn(far))
        player:moveTo(11, 11, 1)
        switch(game, player, heater, true)
        assert.is_false(isOn(heater))
        player:moveTo(11, 11, 0)
        command(game, player, "device_switch", heater, { active = true, fullType = "Base.Hammer" })
        command(game, player, "device_switch", heater, { active = true, x = "nowhere" })
        command(game, player, "something_else", heater, { active = true })
        game.events.OnClientCommand.trigger("OtherMod", "device_switch", player, args(heater, { active = true }))
        assert.is_false(isOn(heater))
        assert.are.equal(0, #broadcasts(game))
        switch(game, player, heater, true)
        assert.is_true(isOn(heater))
    end)

    it("switch off within a minute once their power is gone", function()
        local game, world, _, Climate = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        game.power = false
        game.advance(1)
        assert.is_false(isOn(heater))
        assert.is_false(broadcasts(game)[2].active)
        assert.are.equal(0, assert(Climate).sample(player).heaterCount)
    end)

    it("run the propane heater on its tank: insert, burn, run dry, replace and remove", function()
        local game, world = House.setup({ power = false })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, PROPANE)
        local tank = player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 0.5 }))
        game.advance(1)
        switch(game, player, heater, true)
        assert.is_false(isOn(heater))
        command(game, player, "device_tank", heater, { action = "insert", tankId = tank:getID() })
        assert.are.equal(0, #player:getInventory().items)
        assert.are.same({ true, 0.5 }, { heater:getItem():getModData().ICLPropaneTankPresent,
            heater:getItem():getModData().ICLPropaneFuel })
        switch(game, player, heater, true)
        assert.is_true(isOn(heater))
        game.advance(240)
        assert.near(0.4, heater:getItem():getModData().ICLPropaneFuel, 0.001)
        -- A state message on every whole percent burned (and the switch on).
        assert.is_true(#broadcasts(game) >= 10)
        game.advance(16 * 60 + 5)
        assert.is_false(isOn(heater))
        assert.are.equal(0, heater:getItem():getModData().ICLPropaneFuel)

        -- Replacing hands back the old tank with what is left in it (here nothing).
        local fresh = player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 1 }))
        command(game, player, "device_tank", heater, { action = "insert", tankId = fresh:getID() })
        local items = player:getInventory().items
        assert.are.same({ 1, 0 }, { #items, items[1]:getCurrentUsesFloat() })
        switch(game, player, heater, true)
        game.advance(60)
        local other = player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 0.8 }))
        command(game, player, "device_tank", heater, { action = "insert", tankId = other:getID() })
        -- Replacing also switches it off.
        assert.is_false(isOn(heater))
        assert.are.equal(2, #items)
        assert.near(0.975, items[2]:getCurrentUsesFloat(), 0.001)
        assert.are.equal(0.8, heater:getItem():getModData().ICLPropaneFuel)
        command(game, player, "device_tank", heater, { action = "remove" })
        assert.is_nil(heater:getItem():getModData().ICLPropaneTankPresent)
        assert.are.equal(3, #items)
        assert.are.equal(0.8, items[3]:getCurrentUsesFloat())
        -- The server tells the client about the items it moved.
        assert.are.equal("remove", game.itemsSent[1][1])
        assert.are.equal("add", game.itemsSent[#game.itemsSent][1])
    end)

    it("take a tank the player holds out of their hands", function()
        local game, world = House.setup({ power = false })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, PROPANE)
        local tank = player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 1 }))
        player:setPrimaryHandItem(tank)
        player:setSecondaryHandItem(tank)
        game.advance(1)
        command(game, player, "device_tank", heater, { action = "insert", tankId = tank:getID() })
        assert.is_true(heater:getItem():getModData().ICLPropaneTankPresent)
        assert.are.equal(0, #player:getInventory().items)
        assert.is_nil(player:getPrimaryHandItem())
        assert.is_nil(player:getSecondaryHandItem())
    end)

    it("will not take an empty tank, a tank the player does not have, or a tank for an electric heater", function()
        local game, world = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local propane = world:device(11, 12, 0, PROPANE)
        local electric = world:device(12, 12, 0, STANDARD)
        local empty = player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 0 }))
        local full = player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 1 }))
        game.advance(1)
        command(game, player, "device_tank", propane, { action = "insert", tankId = empty:getID() })
        command(game, player, "device_tank", propane, { action = "insert", tankId = 999 })
        command(game, player, "device_tank", propane, { action = "remove" })
        command(game, player, "device_tank", electric, { action = "insert", tankId = full:getID() })
        assert.are.equal(2, #player:getInventory().items)
        assert.is_nil(propane:getItem():getModData().ICLPropaneTankPresent)
        assert.is_nil(electric:getItem():getModData().ICLPropaneTankPresent)
    end)

    it("draw on the nearest generator while the grid is off, and stop when it runs dry", function()
        local game, world = House.setup({ power = false })
        local player = world:player(11, 11, 0)
        local generator = world:generator(8, 8, 0, { fuel = 1 })
        local heater = world:device(11, 12, 0, STANDARD)
        local fan = world:device(12, 12, 0, FAN)
        game.advance(1)
        switch(game, player, heater, true)
        switch(game, player, fan, true)
        game.advance(60)
        assert.near(1 - 0.04 - 0.20, generator.fuel, 0.01)
        assert.is_true(generator.synced > 0)
        game.advance(4 * 60)
        assert.is_false(generator.activated)
        assert.are.equal(0, generator.fuel)
        assert.is_true(generator.refreshed > 0)
        assert.is_false(isOn(heater))
        assert.is_false(isOn(fan))
    end)

    it("leave generator fuel alone while the grid is on", function()
        local game, world = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local generator = world:generator(8, 8, 0, { fuel = 1 })
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        game.advance(120)
        assert.are.equal(1, generator.fuel)
        assert.is_true(isOn(heater))
    end)

    it("catch up on fuel for at most MaxElapsedHours after being unloaded", function()
        local game, world = House.setup({ power = false })
        local player = world:player(11, 11, 0)
        local generator = world:generator(8, 8, 0, { fuel = 20 })
        -- Switched on 500 hours ago and found again now.
        world:device(11, 12, 0, STANDARD, { on = true, fuelHour = game.minutes / 60 - 500, at = "11:12:0" })
        game.events.LoadGridsquare.trigger(world:square(11, 12, 0))
        game.advance(1)
        assert.near(20 - 168 * 0.04, generator.fuel, 0.01)
    end)

    it("are found switched on around players within ten minutes, and on squares that load", function()
        local game, world, _, Climate = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        game.advance(1)
        world:device(12, 12, 0, PREMIUM, { on = true, fuelHour = game.minutes / 60 })
        game.advance(10)
        assert.are.equal(1, assert(Climate).sample(player).heaterCount)
        world:device(14, 12, 0, STANDARD, { on = true, fuelHour = game.minutes / 60 })
        game.events.LoadGridsquare.trigger(world:square(14, 12, 0))
        game.advance(0.1)
        assert.are.equal(2, Climate.sample(player).heaterCount)
    end)

    it("come back off when one switched on was picked up and put down elsewhere", function()
        local game, world = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        world:pickUp(heater)
        game.events.OnObjectAboutToBeRemoved.trigger(heater)
        local moved = world:device(12, 11, 0, STANDARD, { on = true, fuelHour = game.minutes / 60, at = "11:12:0" })
        game.events.OnObjectAdded.trigger(moved)
        assert.is_false(isOn(moved))
        -- A device from an older save (no position kept) stays on.
        local old = world:device(12, 13, 0, STANDARD, { on = true, fuelHour = game.minutes / 60 })
        game.events.OnObjectAdded.trigger(old)
        assert.is_true(isOn(old))
    end)

    it("are forgotten when picked up", function()
        local game, world, _, Climate = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        game.events.OnObjectAboutToBeRemoved.trigger(heater)
        world:pickUp(heater)
        assert.are.equal(0, assert(Climate).sample(player).heaterCount)
    end)

    it("are told to a client that joins", function()
        local game, world = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        game.events.OnClientCommand.trigger(Sync.MODULE, Sync.HELLO, player, {})
        local told = {}
        for _, message in ipairs(game.sent) do
            if message.player == player and message.command == "device_state" then
                told[#told + 1] = message.args
            end
        end
        assert.are.equal(1, #told)
        assert.is_true(told[1].active)
    end)

    it("change the sample as the player walks about the room, and it is sent", function()
        local game, world, _, Climate = House.setup({ power = true })
        local player = world:player(10, 10, 0)
        local heater = world:device(12, 13, 0, STANDARD)
        game.advance(1)
        player:moveTo(12, 12, 0)
        game.advance(0.1)
        switch(game, player, heater, true)
        local near = assert(Climate).sample(player).airC
        player:moveTo(10, 10, 0)
        game.advance(0.1)
        local far = Climate.sample(player)
        assert.is_true(far.airC < near)
        assert.near(12 * (1 - math.sqrt(13) / 6), far.heaterDeltaC, 1e-9)
        local sent = {}
        for _, message in ipairs(game.sent) do
            if message.player == player and message.command == Sync.SAMPLE then
                sent[#sent + 1] = message.args
            end
        end
        assert.near(far.airC, sent[#sent].airC, 1e-9)
        assert.are.equal(1, sent[#sent].heaterCount)
    end)
end)

insulate("heater heat sources on a dedicated server", function()
    it("are placed for the online players, as the server works out body warmth", function()
        local game, world = House.setup({ power = true, sandbox = { NativeBridge = false } })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        local fan = world:device(12, 12, 0, FAN)
        game.advance(1)
        switch(game, player, heater, true)
        switch(game, player, fan, true)
        game.advance(0.1)
        assert.are.equal(1, #game.heatSources)
        assert.are.same({ 11, 12, 6, 40 }, { game.heatSources[1]:getX(), game.heatSources[1]:getY(),
            game.heatSources[1]:getRadius(), game.heatSources[1]:getTemperature() })
        -- The simulation still reads the game's air without them.
        assert.are.equal(10, IndoorClimateLite.getTemperatureSample(player).vanillaAirC)
        switch(game, player, heater, false)
        game.advance(0.1)
        assert.are.equal(0, #game.heatSources)
    end)
end)

insulate("devices on a client", function()
    local function state(game, extra)
        local message = { x = 11, y = 12, z = 0, fullType = STANDARD, active = true, fuelHour = 100,
            tankPresent = false, tankFuel = 0 }
        for name, value in pairs(extra or {}) do
            message[name] = value
        end
        game.events.OnServerCommand.trigger(Sync.MODULE, "device_state", message)
    end

    it("follow the server's state and place the heater's heat source near the player", function()
        local game, world = House.setup({ side = "client", power = true })
        world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        state(game)
        assert.is_true(isOn(heater))
        assert.are.equal(100, heater:getItem():getModData().ICLHeaterFuelHour)
        assert.are.equal(1, #game.heatSources)
        assert.are.same({ 11, 12, 0, 6, 40 }, { game.heatSources[1]:getX(), game.heatSources[1]:getY(),
            game.heatSources[1]:getZ(), game.heatSources[1]:getRadius(), game.heatSources[1]:getTemperature() })
        state(game, { active = false })
        assert.is_false(isOn(heater))
        assert.are.equal(0, #game.heatSources)
    end)

    it("place no heat source for the fan, for a heater without power, or far from the player", function()
        local game, world = House.setup({ side = "client", power = true })
        local player = world:player(11, 11, 0)
        world:device(12, 12, 0, FAN)
        state(game, { x = 12, fullType = FAN })
        assert.are.equal(0, #game.heatSources)
        local heater = world:device(11, 12, 0, PREMIUM)
        state(game, { fullType = PREMIUM })
        assert.are.equal(1, #game.heatSources)
        game.power = false
        game.advance(1)
        assert.are.equal(0, #game.heatSources)
        game.power = true
        game.advance(1)
        assert.are.equal(1, #game.heatSources)
        assert.are.same({ 12, 25 }, { game.heatSources[1]:getRadius(), game.heatSources[1]:getTemperature() })
        -- Premium radius 12 + 6: a player 19 tiles away is too far.
        world:ground(25, 0, 35, 20)
        player:moveTo(30, 12, 0)
        game.advance(1)
        assert.are.equal(0, #game.heatSources)
        player:moveTo(11, 11, 0)
        game.advance(1)
        assert.are.equal(1, #game.heatSources)
        assert.is_true(isOn(heater))
    end)

    it("set the propane heater's tank from the server", function()
        local game, world = House.setup({ side = "client" })
        world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, PROPANE)
        state(game, { fullType = PROPANE, active = false, tankPresent = true, tankFuel = 0.42 })
        assert.are.equal(0.42, heater:getItem():getModData().ICLPropaneFuel)
        state(game, { fullType = PROPANE, active = true, tankPresent = true, tankFuel = 0.42 })
        assert.are.equal(1, #game.heatSources)
        state(game, { fullType = PROPANE, active = false, tankPresent = false })
        assert.is_nil(heater:getItem():getModData().ICLPropaneTankPresent)
        assert.are.equal(0, #game.heatSources)
    end)

    it("are found switched on in squares the client loads, and forgotten on disconnect", function()
        local game, world = House.setup({ side = "client", power = true })
        world:player(11, 11, 0)
        world:device(11, 12, 0, STANDARD, { on = true })
        game.events.LoadGridsquare.trigger(world:square(11, 12, 0))
        game.advance(0.1)
        assert.are.equal(1, #game.heatSources)
        game.events.OnDisconnect.trigger()
        assert.are.equal(0, #game.heatSources)
        world:device(12, 12, 0, STANDARD, { on = true })
        game.advance(1)
        assert.are.equal(2, #game.heatSources)
    end)

    it("ignore malformed state messages", function()
        local game, world = House.setup({ side = "client", power = true })
        world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        state(game, { fullType = "Base.Hammer" })
        state(game, { x = "here" })
        game.events.OnServerCommand.trigger(Sync.MODULE, "device_state", nil)
        assert.is_false(isOn(heater))
    end)

    it("send the player's choices to the server", function()
        local game, world = House.setup({ side = "client", power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        local Devices = require("IndoorClimateRedone/Game/Devices")
        Devices.request(player, Devices.SWITCH, args(heater, { active = true }))
        assert.are.equal(1, #game.clientSent)
        assert.are.same({ player = player, module = Sync.MODULE, command = "device_switch",
            args = args(heater, { active = true }) }, game.clientSent[1])
        assert.is_false(isOn(heater))
    end)
end)

insulate("devices in single player", function()
    it("switch from the menu at once, warm the game's air, and the simulation reads the air without them", function()
        local game, world, _, Climate = House.setup({ side = "sp", power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 11, 0, STANDARD)
        game.advance(1)
        local Devices = require("IndoorClimateRedone/Game/Devices")
        Devices.request(player, Devices.SWITCH, args(heater, { active = true }))
        assert.is_true(isOn(heater))
        assert.are.equal(0, #game.sent)
        game.advance(0.1)
        local sources = 0
        for _, source in ipairs(game.heatSources) do
            if source:getRadius() == 6 then
                sources = sources + 1
            end
        end
        assert.are.equal(1, sources)
        assert.is_true(getClimateManager():getAirTemperatureForSquare(player:getCurrentSquare()) > 30)
        game.advance(5)
        local sample = assert(Climate).sample(player)
        assert.are.equal(10, sample.vanillaAirC)
        assert.near(sample.baseRoomC + 12, sample.airC, 1e-9)
    end)
end)

insulate("device menus", function()
    local function fakeUi()
        local placed = {}
        _G.ISWorldObjectContextMenu = { addToolTip = function() return {} end }
        _G.ISInventoryPaneContextMenu = { onPlaceItemOnGround = function(items, player)
            placed[#placed + 1] = { items = items, player = player }
        end }
        _G.ISInventoryPane = { getActualItems = function(items) return items end }
        return placed
    end

    local function newContext()
        local context = { options = {} }
        function context:addOption(name, target, onSelect, ...)
            local option = { name = name, target = target, onSelect = onSelect, params = { ... } }
            self.options[#self.options + 1] = option
            return option
        end
        return context
    end

    local function pick(context, name)
        for _, option in ipairs(context.options) do
            if option.name == name then
                option.onSelect(option.target, unpack(option.params))
                return option
            end
        end
        error("no option " .. name)
    end

    local function names(context)
        local list = {}
        for _, option in ipairs(context.options) do
            list[#list + 1] = option.name .. (option.notAvailable and " (unavailable)" or "")
        end
        return list
    end

    it("offer turning a device on or off, greyed out without electricity", function()
        fakeUi()
        local game, world = House.setup({ side = "sp", power = false })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        local context = newContext()
        game.events.OnPreFillWorldObjectContextMenu.trigger(0, context, { heater })
        assert.are.same({ "Turn On Heater (unavailable)" }, names(context))
        assert.are.equal("Requires electricity", context.options[1].toolTip.description)
        game.power = true
        context = newContext()
        game.events.OnPreFillWorldObjectContextMenu.trigger(0, context, { heater })
        pick(context, "Turn On Heater")
        assert.is_true(isOn(heater))
        context = newContext()
        local floor = { getSquare = function() return world:square(11, 12, 0) end }
        game.events.OnPreFillWorldObjectContextMenu.trigger(0, context, { floor })
        pick(context, "Turn Off Heater")
        assert.is_false(isOn(heater))
        context = newContext()
        local elsewhere = { getSquare = function() return world:square(14, 12, 0) end }
        game.events.OnPreFillWorldObjectContextMenu.trigger(0, context, { elsewhere })
        assert.are.same({}, names(context))
    end)

    it("show the propane tank and offer inserting, replacing and removing it", function()
        fakeUi()
        local game, world = House.setup({ side = "sp", power = false })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, PROPANE)
        game.advance(1)
        local context = newContext()
        game.events.OnPreFillWorldObjectContextMenu.trigger(0, context, { heater })
        assert.are.same({ "Propane tank: not installed (unavailable)", "Turn On Propane Heater (unavailable)" },
            names(context))
        assert.are.equal("Requires a non-empty propane tank", context.options[2].toolTip.description)
        player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 0.73 }))
        context = newContext()
        game.events.OnPreFillWorldObjectContextMenu.trigger(0, context, { heater })
        pick(context, "Insert Propane Tank")
        context = newContext()
        player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 1 }))
        game.events.OnPreFillWorldObjectContextMenu.trigger(0, context, { heater })
        assert.are.same({ "Propane: 73% (unavailable)", "Replace Propane Tank", "Remove Propane Tank",
            "Turn On Propane Heater" }, names(context))
        pick(context, "Remove Propane Tank")
        assert.is_nil(heater:getItem():getModData().ICLPropaneTankPresent)
        assert.are.equal(2, #player:getInventory().items)
    end)

    it("install a device from the inventory with the game's place-item tool", function()
        local placed = fakeUi()
        local game, world = House.setup({ side = "sp" })
        local player = world:player(11, 11, 0)
        local fan = player:getInventory():AddItem(world:item(FAN))
        fan.modData.ICLHeaterActive = true
        local context = newContext()
        game.events.OnPreFillInventoryObjectContextMenu.trigger(0, context, { world:item("Base.Hammer"), fan })
        assert.are.same({ "Install Standing Fan" }, names(context))
        pick(context, "Install Standing Fan")
        assert.are.same({ { items = { fan }, player = player } }, placed)
        assert.is_nil(fan.modData.ICLHeaterActive)
        fan.favorite = true
        context = newContext()
        game.events.OnPreFillInventoryObjectContextMenu.trigger(0, context, { fan })
        assert.are.same({ "Install Standing Fan (unavailable)" }, names(context))
    end)
end)

insulate("devices in the public API", function()
    it("warm getTemperatureForSquare and the sample outside the simulated rooms too", function()
        local game, world = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, STANDARD)
        game.advance(1)
        switch(game, player, heater, true)
        local room = IndoorClimateLite.getTemperatureSample(player).baseRoomC
        assert.near(room + 12, IndoorClimateLite.getTemperatureForSquare(world:square(11, 12, 0), player), 1e-9)
        -- Outdoors, three tiles from the heater: the game's air (10) and half the heater's 12.
        assert.near(16, IndoorClimateLite.getTemperatureForSquare(world:square(11, 9, 0), player), 1e-9)
        local outside = world:player(9, 12, 0)
        game.advance(0.1)
        local s = IndoorClimateLite.getTemperatureSample(outside)
        assert.is_nil(s.roomKey)
        assert.are.equal(1, s.heaterCount)
        assert.near(10 + 12 * (1 - 2 / 6), s.airC, 1e-9)
    end)

    it("give Extensive Health Redone a room sample on a dedicated server", function()
        -- What Health Redone checks before it uses a sample (its Game/IndoorClimate.sample).
        local game, world = House.setup({ power = true })
        local player = world:player(11, 11, 0)
        local heater = world:device(11, 12, 0, PREMIUM)
        game.advance(30)
        switch(game, player, heater, true)
        local s = IndoorClimateLite.getTemperatureSample(player)
        assert.is_true(isServer())
        assert.is_true(IndoorClimateLite.isActive())
        assert.is_not_nil(IndoorClimateLite.getRoomDescriptor(player:getCurrentSquare()))
        assert.are.equal("IndoorClimateLite", s.source)
        assert.is_true(s.active)
        assert.is_true(s.indoors)
        assert.is_not_nil(s.roomKey)
        assert.are.equal("number", type(s.airC))
        assert.is_true(s.airC >= -50 and s.airC <= 50)
        assert.is_true(s.airC > s.baseRoomC)
    end)
end)

insulate("generator info window", function()
    it("lists the devices a generator powers and adds their draw to the total", function()
        local game, world = House.setup({ side = "sp", power = false })
        local player = world:player(11, 11, 0)
        local generator = world:generator(8, 8, 0)
        game.advance(1)
        local Devices = require("IndoorClimateRedone/Game/Devices")
        for _, at in ipairs({ { 11, 12, STANDARD }, { 12, 12, STANDARD }, { 12, 11, FAN }, { 10, 11, PROPANE } }) do
            local device = world:device(at[1], at[2], 0, at[3], { tank = 1 })
            Devices.request(player, Devices.SWITCH, args(device, { active = true }))
        end
        local GeneratorInfo = require("IndoorClimateRedone/GeneratorInfo")
        local config = IndoorClimateLite.refreshConfig()
        local load = GeneratorInfo.load(generator, config)
        assert.are.equal(3, load.count)
        assert.near(0.28, load.totalLph, 1e-9)
        assert.are.same({ "ElectricHeater", "StandingFan" }, { load.entries[1].label, load.entries[2].label })
        local original = "IGUI_Generator_TypeGas (0.020 L/h) <LINE> IGUI_Total: 0.030 L/h <LINE> "
        local text = GeneratorInfo.text(original, generator, config)
        assert.are.equal("ElectricHeater x2 (0.080 L/h) <LINE> StandingFan x1 (0.200 L/h) <LINE> "
            .. "IGUI_Generator_TypeGas (0.020 L/h) <LINE> IGUI_Total: 0.310 L/h <LINE> ", text)
        game.power = true
        game.realMs = game.realMs + 2000
        assert.are.equal(original, GeneratorInfo.text(original, generator, config))
    end)

    it("wraps the vanilla window once at game start", function()
        local calls = 0
        _G.ISGeneratorInfoWindow = { getRichText = function()
            calls = calls + 1
            return "vanilla"
        end }
        local game, world = House.setup({ side = "sp", power = false })
        world:player(11, 11, 0)
        local generator = world:generator(8, 8, 0)
        game.events.OnGameStart.trigger()
        game.events.OnGameStart.trigger()
        assert.are.equal("vanilla", ISGeneratorInfoWindow.getRichText(generator, true))
        assert.are.equal(1, calls)
        assert.are.equal(1.5, require("IndoorClimateRedone/GeneratorInfo").parseLph("1,5 L/h"))
    end)
end)
