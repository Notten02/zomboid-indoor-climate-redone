-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The room simulation as the game drives it (Main wired to fake events): occupied zones, room states in world
-- data, stepping on the UpdateMinutes clock and on room changes, catching up, power cuts and samples.
local FakeGame = require("support/fake_game")
local FakeWorld = require("support/fake_world")
local House = require("support/house")

local KEY = House.KEY
local fresh = House.fresh

-- The two-room house on a dedicated server (opts.server = false: single player).
local function setup(opts)
    opts = opts or {}
    return House.setup({ side = opts.server == false and "sp" or "server", power = opts.power,
        sandbox = opts.sandbox })
end

local function hours(game)
    return game.minutes / 60
end

insulate("Climate", function()
    local Config = require("IndoorClimateRedone/Config")
    local Model = require("IndoorClimateRedone/Model")
    local config = Config.defaults()

    it("starts a house nobody visited at outdoor air plus 2 C", function()
        local game, world, _, Climate = setup()
        local player = world:player(11, 11, 0)
        game.advance(1)
        local sample = Climate.sample(player)
        assert.near(12, sample.airC, 0.01)
        assert.are.equal(KEY, sample.buildingKey)
        assert.are.equal("vanilla:1", sample.roomKey)
        assert.are.equal("vanilla", sample.roomKind)
        assert.is_true(sample.indoors)
        assert.is_false(sample.powered)
        assert.are.equal(10, sample.outdoorC)
        assert.is_true(sample.envelopeComplete)
        assert.are.equal(2, sample.thermalRoomCount)
        assert.are.equal(1, sample.thermalEdgeCount)
        assert.are.equal(3, sample.cachedOpenings)
    end)

    it("heats a powered house toward 22 C", function()
        local game, world, _, Climate = setup({ power = true })
        local player = world:player(11, 11, 0)
        game.advance(0.1)
        local start = hours(game)
        game.advance(120)
        local sample = Climate.sample(player)
        assert.near(Model.advance(12, 22, sample.hour - start, 3.0), sample.airC, 1e-6)
        assert.near(22, sample.targetC, 1e-9)
        assert.is_true(sample.powered)
    end)

    it("keeps room states in world data across a restart", function()
        local game, world, _, Climate = setup({ power = true })
        local player = world:player(11, 11, 0)
        game.advance(60)
        local data = game.modData.IndoorClimateRedone
        assert.are.equal(1, data.version)
        local saved = data.zones[KEY]
        assert.is_not_nil(saved.roomStates["vanilla:1"])
        assert.is_not_nil(saved.roomStates["vanilla:2"])
        local before = Climate.sample(player).airC

        game.events.OnInitGlobalModData.trigger(true)
        assert.is_nil(Climate.sample(player))
        game.power = false
        game.advance(1)
        assert.are.equal(saved, game.modData.IndoorClimateRedone.zones[KEY])
        assert.near(before, Climate.sample(player).airC, 0.01)
        assert.is_true(Climate.sample(player).airC > 20)
    end)

    it("does not step a house nobody is in, and catches it up on return", function()
        local game, world, _, Climate = setup({ power = true })
        local player = world:player(11, 11, 0)
        game.advance(180)
        local warm = Climate.sample(player).airC
        player:moveTo(5, 5, 0)
        game.advance(0.1)
        assert.is_nil(Climate.sample(player))
        local left = game.modData.IndoorClimateRedone.zones[KEY].lastWorldHour
        game.power = false
        game.advance(600)
        assert.are.equal(left, game.modData.IndoorClimateRedone.zones[KEY].lastWorldHour)
        local offHour = game.modData.IndoorClimateRedone.power.offHour
        assert.is_true(offHour > left)
        player:moveTo(11, 11, 0)
        game.advance(0.1)
        local sample = Climate.sample(player)
        local expected = Model.step(config, warm, offHour - left, true, 10, 10, 0)
        expected = Model.step(config, expected, sample.hour - offHour, false, 10, 10, 0)
        assert.near(expected, sample.airC, 1e-6)
        assert.is_true(sample.airC < warm)
        assert.is_true(sample.airC > 15)
    end)

    it("serves two players in one house from one state", function()
        local game, world, _, Climate = setup()
        local a = world:player(11, 11, 0)
        local b = world:player(14, 12, 0)
        game.advance(2)
        assert.are.equal("vanilla:1", Climate.sample(a).roomKey)
        assert.are.equal("vanilla:2", Climate.sample(b).roomKey)
        assert.are.equal(Climate.sample(a).buildingKey, Climate.sample(b).buildingKey)
        local count = 0
        for _ in pairs(game.modData.IndoorClimateRedone.zones) do
            count = count + 1
        end
        assert.are.equal(1, count)
    end)

    it("steps every UpdateMinutes, and at once when a player changes room", function()
        local game, world, _, Climate = setup({ sandbox = { UpdateMinutes = 5 } })
        local player = world:player(11, 11, 0)
        game.advance(0.1)
        local first = Climate.sample(player).hour
        game.advance(3)
        assert.are.equal(first, Climate.sample(player).hour)
        game.advance(3)
        local second = Climate.sample(player).hour
        assert.near(first + 5 / 60, second, 0.02)
        player:moveTo(14, 12, 0)
        game.advance(0.1)
        assert.are.equal("vanilla:2", Climate.sample(player).roomKey)
        assert.is_true(Climate.sample(player).hour > second)
    end)

    it("sees a door opened or a window smashed at the next step", function()
        local game, world, o, Climate = setup()
        local player = world:player(11, 11, 0)
        game.advance(1)
        assert.are.equal(0, Climate.sample(player).leakScore)
        o.front.open = true
        game.advance(1)
        assert.are.equal(1, Climate.sample(player).leakScore)
        assert.are.equal(1, Climate.sample(player).openDoors)
        o.front.open = false
        o.west.smashed = true
        game.advance(1)
        assert.near(0.85, Climate.sample(player).leakScore, 1e-9)
        assert.are.equal(1, Climate.sample(player).openWindows)
    end)

    it("learns the stairs a player walks between floors", function()
        local game = FakeGame.install({ server = true })
        local world = FakeWorld.install(game)
        world:building({ x = 0, y = 0, w = 3, h = 3, rooms = {
            { id = 1, x1 = 0, y1 = 0, x2 = 2, y2 = 2 },
            { id = 2, x1 = 0, y1 = 0, x2 = 2, y2 = 2, z = 1 },
        } })
        fresh()
        require("IndoorClimateRedone/Main")
        game.events.OnInitGlobalModData.trigger(false)
        local Climate = require("IndoorClimateRedone/Climate")
        local Envelope = require("IndoorClimateRedone/Envelope")
        local player = world:player(1, 1, 0)
        game.advance(1)
        player:moveTo(1, 1, 1)
        game.advance(1)
        assert.are.equal("vanilla:2", Climate.sample(player).roomKey)
        local edges = Envelope.model(Envelope.get("building:x0:y0:w3:h3")).edges
        assert.are.equal(1, #edges)
        assert.is_true(edges[1].learned)
    end)

    it("simulates a player-built room as one zone", function()
        local game, world, _, Climate = setup()
        world:ground(28, 28, 33, 33)
        world:region({ { 30, 30 }, { 31, 30 } }, 0, { id = 9 })
        world:thumpable(30, 30, 0, "N", "window", { open = true })
        local player = world:player(31, 30, 0)
        game.advance(1)
        local sample = Climate.sample(player)
        assert.are.equal("player:region:9:z0", sample.buildingKey)
        assert.are.equal("player", sample.roomKind)
        assert.near(0.70, sample.leakScore, 1e-9)
    end)

    it("uses the nearby scan for a map room outside any building", function()
        local game, world, _, Climate = setup()
        world:building({ x = 40, y = 40, w = 2, h = 2, detached = true, rooms = { { id = 9, x1 = 40, y1 = 40,
            x2 = 41, y2 = 41 } } })
        world:door(40, 40, 0, "W", { open = true })
        local player = world:player(41, 41, 0)
        game.advance(1)
        local sample = Climate.sample(player)
        assert.are.equal("vanilla:9", sample.buildingKey)
        assert.are.equal(1, sample.leakScore)
        assert.is_nil(sample.envelopeComplete)
    end)

    it("has no sample outdoors, in a vehicle, when disabled or next to a conflicting mod", function()
        local game, world, _, Climate = setup()
        local player = world:player(11, 11, 0)
        game.advance(1)
        assert.is_not_nil(Climate.sample(player))
        player.vehicle = {}
        game.advance(0.1)
        assert.is_nil(Climate.sample(player))
        player.vehicle = nil
        game.advance(0.1)
        assert.is_not_nil(Climate.sample(player))
        game.sandbox.Enabled = false
        game.advance(1)
        assert.is_nil(Climate.sample(player))
        game.sandbox.Enabled = true
        game.mods.RealisticTemperature = true
        game.advance(1)
        assert.is_nil(Climate.sample(player))
        game.mods.RealisticTemperature = nil
        game.advance(1)
        assert.is_not_nil(Climate.sample(player))
    end)

    it("takes over a house the player saved with the original mod", function()
        local game, world, _, Climate = setup()
        local player = world:player(11, 11, 0)
        player.modData.IndoorClimateLite = { version = 1, rooms = { [KEY] = { temperature = 3,
            lastWorldHour = hours(game), lastPowered = false, roomStates = {
                ["vanilla:1"] = { temperature = 3, lastWorldHour = hours(game), lastPowered = false, area = 12 } } } } }
        game.advance(1)
        assert.near(3, Climate.sample(player).airC, 0.05)
        assert.is_not_nil(player.modData.IndoorClimateLite.rooms[KEY])
        assert.is_true(game.logged("took over 1 building states"))
    end)

    it("runs the same in single player", function()
        local game, world, _, Climate = setup({ server = false })
        local player = world:player(11, 11, 0)
        game.advance(1)
        assert.near(12, Climate.sample(player).airC, 0.01)
    end)

    it("shares the scan budget between zones", function()
        local game = FakeGame.install({ server = true })
        local world = FakeWorld.install(game)
        fresh()
        local Envelope = require("IndoorClimateRedone/Envelope")
        require("IndoorClimateRedone/Main")
        game.events.OnInitGlobalModData.trigger(false)
        local keys = {}
        for i = 1, 8 do
            local x = i * 40
            world:building({ x = x, y = 0, w = 20, h = 20, rooms = { { id = i, x1 = x, y1 = 0, x2 = x + 19,
                y2 = 19 } } })
            world:player(x + 1, 1, 0)
            keys[i] = string.format("building:x%d:y0:w20:h20", x)
        end
        local function scanned()
            local total = 0
            for _, key in ipairs(keys) do
                local cache = Envelope.get(key)
                total = total + (cache and cache.squaresScanned or 0)
            end
            return total
        end
        game.advance(0.1)
        assert.are.equal(config.ServerScanBudget, scanned())
        game.advance(0.9)
        local total = scanned()
        assert.is_true(total > config.ServerScanBudget and total <= 2 * config.ServerScanBudget, total)
        game.advance(2)
        for _, key in ipairs(keys) do
            assert.is_true(Envelope.get(key).complete, key)
        end
    end)

    it("steps the zone of a square on request, with or without a player in it", function()
        local game, world, _, Climate = setup({ power = true })
        assert.is_true(Climate.stepSquare(world:square(14, 12, 0), hours(game)))
        local state = game.modData.IndoorClimateRedone.zones[KEY]
        assert.near(12, state.roomStates["vanilla:2"].temperature, 1e-9)
        assert.is_false(Climate.stepSquare(world:square(5, 5, 0), hours(game)))
        local player = world:player(11, 11, 0)
        game.advance(0.1)
        game.advance(30)
        local before = Climate.sample(player).hour
        assert.is_true(Climate.stepSquare(world:square(14, 12, 0), hours(game) + 0.01))
        assert.is_true(Climate.sample(player).hour > before)
    end)

    it("logs its cost once a game hour with debug logging on", function()
        local game, world = setup({ sandbox = { DebugLogging = true } })
        world:player(11, 11, 0)
        game.advance(61)
        assert.is_true(game.logged("cost over 1.0 h"))
        assert.is_true(game.logged("building=" .. KEY .. " room=vanilla:1"))
    end)
end)
