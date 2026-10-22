-- LuaLS's bundled luassert definitions omit the optional failure-message argument; the mod stand-ins are partial.
---@diagnostic disable: redundant-parameter, missing-fields
-- Lua Digital Watch UI and Unseasonal Weather's clock show the room air indoors, hooked at game start.
local House = require("support/house")

-- A stand-in for Lua Digital Watch UI's API (LuaDigitalWatch/LuaDigitalWatch.lua): the parts the mod uses.
local function fakeWatch()
    local Watch = { _overrides = {}, _handlers = {}, inits = 0 }
    function Watch.init() Watch.inits = Watch.inits + 1 end
    function Watch.setTemperatureResolver(fn) Watch._temperatureResolver = fn end
    function Watch.getTemperatureResolver() return Watch._temperatureResolver end
    function Watch.setOverride(key, value)
        Watch._overrides[key] = value
        return true
    end
    function Watch.clearOverride(key) return Watch.setOverride(key, nil) end
    function Watch:getOverrides() return Watch._overrides end
    function Watch.getInstance() return Watch.instance end
    function Watch.on(name, fn) Watch._handlers[name] = fn end
    -- What the watch would show: an override, else the resolver.
    function Watch.shown(player)
        if Watch._overrides.temperature ~= nil then
            return Watch._overrides.temperature
        end
        return Watch._temperatureResolver(player, nil)
    end
    package.preload["LuaDigitalWatch/LuaDigitalWatch"] = function() return Watch end
    package.loaded["LuaDigitalWatch/LuaDigitalWatch"] = nil
    return Watch
end

insulate("Lua Digital Watch UI", function()
    it("is hooked at game start, not when the mod loads", function()
        local Watch = fakeWatch()
        local game, world = House.setup({ side = "sp", power = true })
        world:player(11, 11, 0)
        assert.is_nil(Watch._temperatureResolver)
        game.events.OnGameStart.trigger()
        assert.are.equal("function", type(Watch._temperatureResolver))
        assert.are.equal(1, Watch.inits)
        assert.are.equal("function", type(Watch._handlers["watch:state_resolved"]))
    end)

    it("shows the room air indoors and what it showed before elsewhere", function()
        local Watch = fakeWatch()
        Watch.setTemperatureResolver(function() return -3 end)
        local game, world, _, Climate = House.setup({ side = "sp", power = true })
        local player = world:player(11, 11, 0)
        game.events.OnGameStart.trigger()
        game.advance(60)
        local room = assert(Climate).sample(player).airC
        assert.is_true(room > 15)
        assert.are.equal(room, Watch._temperatureResolver(player))
        -- The watch resolves its state on every update.
        Watch._handlers["watch:state_resolved"]()
        assert.are.equal(room, Watch.shown(player))
        player:moveTo(5, 5, 0)
        game.advance(1)
        assert.are.equal(-3, Watch._temperatureResolver(player))
        assert.are.equal(-3, Watch.shown(player))
        player.vehicle = {}
        player:moveTo(11, 11, 0)
        game.advance(1)
        assert.are.equal(-3, Watch.shown(player))
    end)

    it("uses the game's air for the character when nothing read it before", function()
        local Watch = fakeWatch()
        local game, world = House.setup({ side = "sp", power = false })
        local player = world:player(5, 5, 0)
        game.climate.vanillaC = 7
        game.events.OnGameStart.trigger()
        assert.are.equal(7, Watch._temperatureResolver(player))
    end)

    it("lets go of its own override only", function()
        local Watch = fakeWatch()
        local game, world = House.setup({ side = "sp", power = true })
        local player = world:player(11, 11, 0)
        game.events.OnGameStart.trigger()
        game.advance(5)
        assert.is_not_nil(Watch._overrides.temperature)
        player:moveTo(5, 5, 0)
        game.advance(1)
        assert.is_nil(Watch._overrides.temperature)
        player:moveTo(11, 11, 0)
        game.advance(1)
        Watch._overrides.temperature = 99
        player:moveTo(5, 5, 0)
        game.advance(1)
        -- Indoors it was set to the room again; another mod changed it to 99, so it stays.
        assert.are.equal(99, Watch._overrides.temperature)
    end)

    it("takes its reader back when another mod replaced it, keeping that one for elsewhere", function()
        local Watch = fakeWatch()
        local game, world = House.setup({ side = "sp", power = true })
        local player = world:player(11, 11, 0)
        game.events.OnGameStart.trigger()
        local ours = Watch._temperatureResolver
        Watch.setTemperatureResolver(function() return 55 end)
        game.advance(1)
        assert.are.equal(ours, Watch._temperatureResolver)
        player:moveTo(5, 5, 0)
        game.advance(0.1)
        assert.are.equal(55, Watch._temperatureResolver(player))
        Watch.setTemperatureResolver(function() return 66 end)
        Watch._handlers["watch:state_resolved"]()
        assert.are.equal(ours, Watch._temperatureResolver)
    end)

    it("does nothing without the watch mod", function()
        package.preload["LuaDigitalWatch/LuaDigitalWatch"] = nil
        package.loaded["LuaDigitalWatch/LuaDigitalWatch"] = nil
        local game, world = House.setup({ side = "sp" })
        world:player(11, 11, 0)
        game.events.OnGameStart.trigger()
        game.advance(1)
        assert.is_false(require("IndoorClimateRedone/Watch").install())
    end)

    it("looks for the watch mod only once when it is missing, since every failed require logs a warning", function()
        package.preload["LuaDigitalWatch/LuaDigitalWatch"] = nil
        package.loaded["LuaDigitalWatch/LuaDigitalWatch"] = nil
        local realRequire = require
        local lookups = 0
        _G.require = function(name)
            if name == "LuaDigitalWatch/LuaDigitalWatch" then
                lookups = lookups + 1
                return nil
            end
            return realRequire(name)
        end
        local game, world = House.setup({ side = "sp" })
        world:player(11, 11, 0)
        game.events.OnGameStart.trigger()
        game.advance(5)
        for _ = 1, 3 * require("IndoorClimateRedone/Watch").REPAIR_TICKS do
            game.events.OnPlayerUpdate.trigger(world.players[1])
        end
        _G.require = realRequire
        assert.are.equal(1, lookups)
    end)
end)

insulate("Unseasonal Weather clock", function()
    it("reads the room air on every clock it creates", function()
        local calls = 0
        _G.UW_DigitalWatchUI = { getDisplayTemperature = function()
            calls = calls + 1
            return 4
        end }
        local game, world, _, Climate = House.setup({ side = "sp", power = true })
        local player = world:player(11, 11, 0)
        game.events.OnGameStart.trigger()
        game.events.OnGameStart.trigger()
        game.advance(5)
        local clock = setmetatable({ clockPlayer = player }, { __index = UW_DigitalWatchUI })
        assert.are.equal(assert(Climate).sample(player).airC, clock:getDisplayTemperature())
        player:moveTo(5, 5, 0)
        game.advance(1)
        assert.are.equal(4, clock:getDisplayTemperature())
        assert.are.equal(1, calls)
    end)
end)
