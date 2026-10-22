-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The envelope scan on the server: rooms, edges and outer-wall openings of a zone, read in budgeted chunks and
-- refreshed by reading known objects again.
local FakeGame = require("support/fake_game")
local FakeWorld = require("support/fake_world")

local KEY = "building:x10:y10:w6:h4"

-- A two-room house: room 1 (west, 3x4) and room 2 (east, 3x4), a door between them at y 11 and an archway at y 12,
-- a front door in room 1's west wall, a window in each room's north wall, and a window frame in room 2's south wall.
local function house()
    local game = FakeGame.install({ server = true })
    local world = FakeWorld.install(game)
    world:building({ x = 10, y = 10, w = 6, h = 4, rooms = {
        { id = 1, x1 = 10, y1 = 10, x2 = 12, y2 = 13 },
        { id = 2, x1 = 13, y1 = 10, x2 = 15, y2 = 13 },
    } })
    local o = {
        inner = world:door(13, 11, 0, "W"),
        front = world:door(10, 12, 0, "W"),
        west = world:window(11, 10, 0, "N"),
        east = world:window(14, 10, 0, "N"),
        frame = world:frame(14, 14, 0, "N", { hasWindow = true }),
    }
    world:passage(13, 12, 0, "W")
    local Config = require("IndoorClimateRedone/Config")
    local Places = require("IndoorClimateRedone/Game/Places")
    local Envelope = require("IndoorClimateRedone/Envelope")
    Envelope.clear()
    return world, o, Config.defaults(), Places, Envelope
end

local function edgeOf(model, key)
    for _, edge in ipairs(model.edges) do
        if edge.key == key then
            return edge
        end
    end
    return nil
end

insulate("Envelope scan of a map building", function()
    it("finds the rooms, how they join and the openings in the outer wall", function()
        local world, o, config, Places, Envelope = house()
        local d = Places.describe(world:square(11, 11, 0))
        local cache, visited = Envelope.refresh(config, d, 5, 300)
        assert.are.equal(24, visited)
        assert.is_true(cache.complete)
        assert.is_false(cache.partial)

        local model = Envelope.model(cache)
        assert.are.same({ area = 12, z = 0 }, model.rooms["vanilla:1"])
        assert.are.same({ area = 12, z = 0 }, model.rooms["vanilla:2"])
        local edge = edgeOf(model, "vanilla:1|vanilla:2")
        assert.are.equal(1, edge.doors)
        assert.are.equal(1, edge.passages)
        assert.are.equal(2, edge.walls)
        assert.are.equal(0, edge.openDoors)

        local info = Envelope.leaks(cache)
        assert.are.equal(4, info.openingCount)
        assert.are.equal(0, info.leakScore)
        assert.are.equal(2, info.roomCount)
        assert.are.equal(1, info.edgeCount)
        assert.are.equal(24, info.buildingSquaresSeen)
        local rooms = {}
        for _, record in ipairs(cache.openings) do
            rooms[record.object] = record.roomKey
        end
        assert.are.equal("vanilla:1", rooms[o.front])
        assert.are.equal("vanilla:1", rooms[o.west])
        assert.are.equal("vanilla:2", rooms[o.east])
        assert.are.equal("vanilla:2", rooms[o.frame])
        assert.is_nil(rooms[o.inner])
    end)

    it("reads the openings again on every update, without a rescan", function()
        local world, o, config, Places, Envelope = house()
        local d = Places.describe(world:square(11, 11, 0))
        local cache = Envelope.refresh(config, d, 5, 300)
        o.front.open = true
        o.east.smashed = true
        o.east.barricades = { { planks = 2 } }
        o.frame.withWindow = false
        o.inner.open = true
        local _, visited = Envelope.refresh(config, d, 5.1, 300)
        assert.are.equal(0, visited)
        local info = Envelope.leaks(cache)
        assert.are.equal(1, info.openDoors)
        assert.are.equal(2, info.openWindows)
        assert.near(1.0, info.perRoom["vanilla:1"].leakScore, 1e-9)
        assert.near(1.0, info.perRoom["vanilla:2"].leakScore, 1e-9)
        assert.near(0.85 * 0.40 + 0.85, info.perRoom["vanilla:2"].leakUnits, 1e-9)
        assert.are.equal(1, edgeOf(Envelope.model(cache), "vanilla:1|vanilla:2").openDoors)
    end)

    it("scans a large building over several updates within the budget", function()
        local world, _, config, Places, Envelope = house()
        local d = Places.describe(world:square(11, 11, 0))
        local cache, visited = Envelope.refresh(config, d, 5, 10)
        assert.are.equal(10, visited)
        assert.is_false(cache.complete)
        _, visited = Envelope.refresh(config, d, 5, 10)
        assert.are.equal(10, visited)
        _, visited = Envelope.refresh(config, d, 5, 10)
        assert.are.equal(4, visited)
        assert.is_true(cache.complete)
        assert.are.equal(4, Envelope.leaks(cache).openingCount)
        _, visited = Envelope.refresh(config, d, 5, 0)
        assert.are.equal(0, visited)
    end)

    it("rescans when a known opening is gone, and after the refresh interval", function()
        local world, o, config, Places, Envelope = house()
        local d = Places.describe(world:square(11, 11, 0))
        local cache = Envelope.refresh(config, d, 5, 300)
        world:remove(o.west)
        Envelope.leaks(cache)
        assert.is_true(cache.dirty)
        Envelope.refresh(config, d, 5.1, 300)
        assert.are.equal(3, Envelope.leaks(cache).openingCount)

        world:window(12, 10, 0, "N", { open = true })
        Envelope.refresh(config, d, 11.0, 300)
        assert.are.equal(3, Envelope.leaks(cache).openingCount)
        Envelope.refresh(config, d, 11.2, 300)
        assert.are.equal(4, Envelope.leaks(cache).openingCount)
        assert.are.equal(1, Envelope.leaks(cache).openWindows)
    end)

    it("marks a scan that met unloaded map as partial and retries it soon", function()
        local world, _, config, Places, Envelope = house()
        world:unload(14, 0, 99, 99)
        local d = Places.describe(world:square(11, 11, 0))
        local cache = Envelope.refresh(config, d, 5, 300)
        assert.is_true(cache.complete)
        assert.is_true(cache.partial)
        assert.are.equal(8, cache.missingSquares)
        assert.are.equal(16, Envelope.leaks(cache).buildingSquaresSeen)
        world:reload()
        Envelope.refresh(config, d, 5.2, 300)
        assert.is_true(cache.partial)
        Envelope.refresh(config, d, 5.25, 300)
        assert.is_false(cache.partial)
        assert.are.equal(24, Envelope.leaks(cache).buildingSquaresSeen)
    end)

    it("starts over when none of the building is loaded yet", function()
        local world, _, config, Places, Envelope = house()
        local d = Places.describe(world:square(11, 11, 0))
        world:unload(0, 0, 99, 99)
        local cache = Envelope.refresh(config, d, 5, 300)
        assert.is_false(cache.complete)
        world:reload()
        Envelope.refresh(config, d, 5.1, 300)
        assert.is_true(cache.complete)
    end)

    it("sorts edges by key and remembers stairs a player walked", function()
        local game = FakeGame.install({ server = true })
        local world = FakeWorld.install(game)
        world:building({ x = 0, y = 0, w = 4, h = 2, rooms = {
            { id = 30, x1 = 0, y1 = 0, x2 = 1, y2 = 1 },
            { id = 10, x1 = 2, y1 = 0, x2 = 3, y2 = 1 },
            { id = 20, x1 = 0, y1 = 0, x2 = 3, y2 = 1, z = 1 },
        } })
        local Config = require("IndoorClimateRedone/Config")
        local Places = require("IndoorClimateRedone/Game/Places")
        local Envelope = require("IndoorClimateRedone/Envelope")
        local d = Places.describe(world:square(0, 0, 0))
        local cache = Envelope.refresh(Config.defaults(), d, 1, 300)
        local model = Envelope.model(cache)
        assert.are.same({ area = 8, z = 1 }, model.rooms["vanilla:20"])
        assert.are.equal(1, #model.edges)
        assert.are.equal("vanilla:10|vanilla:30", model.edges[1].key)
        Envelope.learnTransition(d.key, "vanilla:30", "vanilla:20")
        Envelope.learnTransition(d.key, "vanilla:20", "vanilla:10")
        model = Envelope.model(cache)
        local keys = {}
        for _, edge in ipairs(model.edges) do
            keys[#keys + 1] = edge.key
        end
        assert.are.same({ "vanilla:10|vanilla:20", "vanilla:10|vanilla:30", "vanilla:20|vanilla:30" }, keys)
        assert.is_true(model.edges[1].learned)
        assert.is_false(model.edges[2].learned)
        -- Learned stairs survive a rescan.
        cache.dirty = true
        Envelope.refresh(Config.defaults(), d, 2, 300)
        assert.are.equal(3, #Envelope.model(cache).edges)
    end)
end)

insulate("Envelope scan of a player-built room", function()
    it("floods the region from the square it was entered from", function()
        local game = FakeGame.install({ server = true })
        local world = FakeWorld.install(game)
        world:ground(0, 0, 10, 10)
        world:region({ { 2, 2 }, { 3, 2 }, { 2, 3 }, { 3, 3 } }, 0, { id = 5 })
        local window = world:thumpable(2, 2, 0, "N", "window", { open = true })
        world:door(3, 4, 0, "N")
        local Config = require("IndoorClimateRedone/Config")
        local Places = require("IndoorClimateRedone/Game/Places")
        local Envelope = require("IndoorClimateRedone/Envelope")
        local config = Config.defaults()
        local d = Places.describe(world:square(3, 3, 0))
        local cache = Envelope.refresh(config, d, 1, 300)
        assert.is_true(cache.complete)
        local info = Envelope.leaks(cache)
        assert.are.equal(4, info.buildingSquaresSeen)
        assert.are.equal(2, info.openingCount)
        assert.near(0.70, info.leakScore, 1e-9)
        assert.near(0.70, info.perRoom["player:region:5:z0"].leakScore, 1e-9)
        window.open = false
        assert.are.equal(0, Envelope.leaks(cache).leakScore)
        -- A room that grew is scanned again.
        world:region({ { 2, 2 }, { 3, 2 }, { 2, 3 }, { 3, 3 }, { 4, 3 } }, 0, { id = 5 })
        Envelope.refresh(config, Places.describe(world:square(3, 3, 0)), 1.1, 300)
        assert.are.equal(5, Envelope.leaks(cache).buildingSquaresSeen)
    end)
end)

insulate("Envelope.nearby", function()
    it("counts open doors and windows of the outer wall near a square, not frames", function()
        local world, o, config, Places, Envelope = house()
        o.front.open = true
        o.west.open = true
        o.east.open = true
        o.frame.withWindow = false
        config.ScanRadius = 2
        local near = Envelope.nearby(config, world:square(10, 11, 0), KEY)
        assert.are.same({ leakScore = 1, openDoors = 1, openWindows = 1 }, near)
        assert.is_not_nil(Places)
    end)
end)

insulate("Envelope.prune", function()
    it("drops the least recently used caches but never a kept one", function()
        local game = FakeGame.install({ server = true })
        local world = FakeWorld.install(game)
        local Config = require("IndoorClimateRedone/Config")
        local Places = require("IndoorClimateRedone/Game/Places")
        local Envelope = require("IndoorClimateRedone/Envelope")
        local keys = {}
        for i = 1, 4 do
            world:building({ x = i * 20, y = 0, w = 2, h = 2, rooms = { { id = i, x1 = i * 20, y1 = 0,
                x2 = i * 20 + 1, y2 = 1 } } })
            local d = Places.describe(world:square(i * 20, 0, 0))
            Envelope.refresh(Config.defaults(), d, i, 300)
            keys[i] = d.key
        end
        Envelope.prune(1, { [keys[1]] = true })
        assert.is_not_nil(Envelope.get(keys[1]))
        assert.is_nil(Envelope.get(keys[2]))
        assert.is_nil(Envelope.get(keys[3]))
        assert.is_not_nil(Envelope.get(keys[4]))
    end)
end)
