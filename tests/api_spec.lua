-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The public API (global IndoorClimateLite): its functions, the sample fields other mods read, the fallbacks
-- outdoors and with the simulation off, and the Realistic Temperature conflict check.
local House = require("support/house")

local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

insulate("IndoorClimateLite API", function()
    it("has the original's functions", function()
        House.setup()
        for _, name in ipairs({ "isActive", "refreshConfig", "getRoomDescriptor", "isIndoorSquare",
            "getTemperatureSample", "getLiveTemperatureSample", "getTemperatureForPlayer",
            "getTemperatureForSquare" }) do
            assert.are.equal("function", type(IndoorClimateLite[name]), name)
        end
        assert.are.equal("string", type(IndoorClimateLite.VERSION))
    end)

    it("reports the mod version from mod.info", function()
        House.setup()
        local version = read("Contents/mods/IndoorClimateRedone/42/mod.info"):match("modversion=([^\r\n]+)")
        assert.are.equal(version, IndoorClimateLite.VERSION)
    end)

    it("keeps fields another mod put on the global table", function()
        _G.IndoorClimateLite = { extra = 1 }
        House.setup()
        assert.are.equal(1, IndoorClimateLite.extra)
        assert.are.equal("function", type(IndoorClimateLite.isActive))
    end)

    it("gives a sample with the original's fields for a player in a simulated room", function()
        local game, world = House.setup({ power = true, sandbox = { PoweredTargetC = 24 } })
        local player = world:player(11, 11, 0)
        game.advance(30)
        local s = IndoorClimateLite.getTemperatureSample(player)
        assert.are.equal("IndoorClimateLite", s.source)
        assert.are.equal(IndoorClimateLite.VERSION, s.version)
        assert.is_true(s.active)
        assert.is_true(s.indoors)
        assert.is_true(s.powered)
        assert.are.equal("vanilla:1", s.roomKey)
        assert.are.equal(House.KEY, s.buildingKey)
        assert.are.equal("number", type(s.airC))
        assert.are.equal(s.airC, s.baseRoomC)
        assert.near(24, s.targetC, 1e-9)
        assert.are.equal(10, s.outdoorC)
        assert.are.equal(10, s.vanillaAirC)
        assert.are.equal(0, s.leakScore)
        assert.are.equal(0, s.openDoors)
        assert.are.equal(0, s.openWindows)
        assert.is_true(s.airC > 12)
        assert.are.equal(s.airC, IndoorClimateLite.getTemperatureForPlayer(player))
    end)

    it("hands out a copy, and the live sample without copying", function()
        local game, world = House.setup()
        local player = world:player(11, 11, 0)
        game.advance(1)
        local live = IndoorClimateLite.getLiveTemperatureSample(player)
        local copy = IndoorClimateLite.getTemperatureSample(player)
        assert.are_not.equal(live, copy)
        assert.are.equal(live.airC, copy.airC)
        copy.airC = -50
        assert.are_not.equal(-50, IndoorClimateLite.getLiveTemperatureSample(player).airC)
        assert.are.equal(live, IndoorClimateLite.getLiveTemperatureSample(player))
    end)

    it("falls back to the game's air outdoors, with indoors false and no room", function()
        local game, world = House.setup()
        game.climate.vanillaC = 7
        local player = world:player(8, 8, 0)
        game.advance(1)
        local s = IndoorClimateLite.getTemperatureSample(player)
        assert.are.equal("IndoorClimateLite", s.source)
        assert.is_true(s.active)
        assert.is_false(s.indoors)
        assert.is_nil(s.roomKey)
        assert.are.equal(7, s.airC)
        assert.are.equal(10, s.outdoorC)
        assert.is_nil(IndoorClimateLite.getLiveTemperatureSample(player))
        assert.are.equal(7, IndoorClimateLite.getTemperatureForPlayer(player))
        assert.are.equal(10, IndoorClimateLite.getTemperatureForPlayer(nil))
        assert.are.equal(10, IndoorClimateLite.getTemperatureForSquare(nil))
    end)

    it("tells the room of a square, nil outdoors", function()
        local _, world = House.setup()
        local d = IndoorClimateLite.getRoomDescriptor(world:square(14, 12, 0))
        assert.are.equal(House.KEY, d.key)
        assert.are.equal("vanilla:2", d.roomKey)
        assert.is_nil(IndoorClimateLite.getRoomDescriptor(world:square(5, 5, 0)))
        assert.is_nil(IndoorClimateLite.getRoomDescriptor(nil))
        assert.is_true(IndoorClimateLite.isIndoorSquare(world:square(14, 12, 0)))
        assert.is_false(IndoorClimateLite.isIndoorSquare(world:square(5, 5, 0)))
    end)

    it("gives a square the saved temperature of its room, and the game's air for an unvisited building", function()
        local game, world, _, server = House.setup({ power = true })
        local Climate = assert(server)
        game.climate.vanillaC = 9
        local player = world:player(11, 11, 0)
        game.advance(120)
        local saved = Climate.data().zones[House.KEY].roomStates["vanilla:2"].temperature
        assert.are.equal(saved, IndoorClimateLite.getTemperatureForSquare(world:square(14, 12, 0), player))
        assert.are.equal(Climate.sample(player).airC,
            IndoorClimateLite.getTemperatureForSquare(world:square(12, 13, 0)))
        world:building({ x = 40, y = 40, w = 3, h = 3, rooms = { { id = 7, x1 = 40, y1 = 40, x2 = 42, y2 = 42 } } })
        assert.are.equal(9, IndoorClimateLite.getTemperatureForSquare(world:square(41, 41, 0)))
        assert.are.equal(9, IndoorClimateLite.getTemperatureForSquare(world:square(8, 8, 0)))
    end)

    it("re-reads the sandbox options on refreshConfig", function()
        local game = House.setup()
        game.sandbox.PoweredTargetC = 25
        local config = IndoorClimateLite.refreshConfig()
        assert.are.equal(IndoorClimateLite.Config, config)
        assert.are.equal(25, config.PoweredTargetC)
        assert.are.equal(1, config.UpdateMinutes)
        game.sandbox.PoweredTargetC = 99
        assert.are.equal(27, IndoorClimateLite.refreshConfig().PoweredTargetC)
    end)

    it("is inactive and gives no room when disabled in the sandbox options", function()
        local game, world = House.setup()
        local player = world:player(11, 11, 0)
        game.advance(1)
        assert.is_true(IndoorClimateLite.isActive())
        game.sandbox.Enabled = false
        IndoorClimateLite.refreshConfig()
        assert.is_false(IndoorClimateLite.isActive())
        local s = IndoorClimateLite.getTemperatureSample(player)
        assert.is_false(s.active)
        assert.is_nil(s.roomKey)
        -- Once the server notices, its bridge heat source at the player goes too.
        game.advance(1)
        assert.are.equal(10, IndoorClimateLite.getTemperatureForSquare(world:square(11, 11, 0)))
    end)

    for _, id in ipairs({ "RC_RealisticColdMod", "RealisticTemperature" }) do
        it("stays off next to Realistic Temperature (" .. id .. ")", function()
            local game, world, _, server = House.setup()
            local Climate = assert(server)
            game.mods[id] = true
            local player = world:player(11, 11, 0)
            game.advance(1)
            IndoorClimateLite.refreshConfig()
            assert.is_false(IndoorClimateLite.isActive())
            assert.is_false(Climate.active())
            assert.is_nil(Climate.sample(player))
            assert.is_false(IndoorClimateLite.getTemperatureSample(player).active)
            assert.is_nil(IndoorClimateLite.getLiveTemperatureSample(player))
        end)
    end

    it("finds the conflicting mod by either ID", function()
        local game = House.setup()
        local Conflicts = require("IndoorClimateRedone/Game/Conflicts")
        assert.is_nil(Conflicts.find())
        game.mods.RC_RealisticColdMod = true
        assert.are.equal("RC_RealisticColdMod", Conflicts.find())
        game.mods.RC_RealisticColdMod = nil
        game.mods.RealisticTemperature = true
        assert.are.equal("RealisticTemperature", Conflicts.find())
        assert.is_true(Conflicts.active())
    end)

    it("works with no player at all (a dedicated server asking for the first local player)", function()
        House.setup()
        local s = IndoorClimateLite.getTemperatureSample(nil)
        assert.are.equal(10, s.airC)
        assert.is_false(s.indoors)
    end)
end)
