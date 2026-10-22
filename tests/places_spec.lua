-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Places and Openings: what zone and room a square is in, and how doors and windows are read.
local FakeGame = require("support/fake_game")
local FakeWorld = require("support/fake_world")

insulate("Places.describe", function()
    local game = FakeGame.install({ server = true })
    local world = FakeWorld.install(game)
    local Places = require("IndoorClimateRedone/Game/Places")
    world:building({ x = 10, y = 20, w = 6, h = 4, rooms = {
        { id = 7, x1 = 10, y1 = 20, x2 = 12, y2 = 23 },
        { id = 8, x1 = 13, y1 = 20, x2 = 15, y2 = 23, z = 1 },
    } })
    world:building({ x = 40, y = 40, w = 2, h = 2, detached = true, rooms = { { id = 9, x1 = 40, y1 = 40, x2 = 41,
        y2 = 41 } } })

    it("describes a map room by its building's bounds and its RoomDef ID", function()
        local d = Places.describe(world:square(11, 21, 0))
        assert.are.equal("building:x10:y20:w6:h4", d.key)
        assert.are.equal("vanilla:7", d.roomKey)
        assert.are.equal("vanilla", d.kind)
        assert.are.equal(24, d.area)
        assert.are.equal(0, d.z)
        assert.is_not_nil(d.buildingDef)
        assert.is_true(Places.hasEnvelope(d))
        assert.are.equal("vanilla:8", Places.roomKey(Places.describe(world:square(14, 21, 1))))
    end)

    it("describes a map room outside any building as a zone of its own", function()
        local d = Places.describe(world:square(40, 40, 0))
        assert.are.equal("vanilla:9", d.key)
        assert.are.equal(4, d.area)
        assert.is_false(Places.hasEnvelope(d))
    end)

    it("describes a fully roofed player-built room by its world region", function()
        world:region({ { 60, 60 }, { 61, 60 } }, 0, { id = 354 })
        world:region({ { 70, 70 } }, 0, { id = 355, roofed = false })
        local d = Places.describe(world:square(60, 60, 0))
        assert.are.equal("player:region:354:z0", d.key)
        assert.are.equal(d.key, d.roomKey)
        assert.are.equal("player", d.kind)
        assert.are.equal(2, d.area)
        assert.is_true(Places.hasEnvelope(d))
        assert.is_nil(Places.describe(world:square(70, 70, 0)))
    end)

    it("has nothing for outdoors or no square", function()
        assert.is_nil(Places.describe(world:square(9, 20, 0)))
        assert.is_nil(Places.describe(nil))
        assert.is_nil(Places.zoneKey(world:square(9, 20, 0)))
    end)
end)

insulate("Openings", function()
    local game = FakeGame.install({ server = true })
    local world = FakeWorld.install(game)
    local Openings = require("IndoorClimateRedone/Game/Openings")
    local Leak = require("IndoorClimateRedone/Leak")
    world:building({ x = 0, y = 0, w = 6, h = 3, rooms = {
        { id = 1, x1 = 0, y1 = 0, x2 = 2, y2 = 2 },
        { id = 2, x1 = 3, y1 = 0, x2 = 5, y2 = 2 },
    } })
    local key = "building:x0:y0:w6:h3"

    it("tells doors, windows and frames apart", function()
        assert.are.equal("door", Openings.kind(world:door(0, 1, 0, "W")))
        assert.are.equal("window", Openings.kind(world:window(1, 0, 0, "N")))
        assert.are.equal("windowFrame", Openings.kind(world:frame(2, 0, 0, "N")))
        assert.are.equal("door", Openings.kind(world:thumpable(4, 0, 0, "N", "door")))
        assert.are.equal("window", Openings.kind(world:thumpable(5, 0, 0, "N", "window")))
        assert.is_nil(Openings.kind({}))
        assert.is_nil(Openings.kind(nil))
    end)

    it("reads the state Leak weighs, with the original's weights", function()
        local door = world:door(0, 2, 0, "W", { open = true })
        assert.are.same({ kind = "door", open = true }, Openings.read(door))
        local boarded = world:window(1, 3, 0, "N", { smashed = true, barricades = { { planks = 2 } } })
        assert.near(0.85 * 0.40, Leak.weight(Openings.read(boarded)), 1e-9)
        local openBarred = world:window(4, 3, 0, "N", { open = true, barricades = { nil, { metalBar = true } } })
        assert.near(0.70 * 0.30, Leak.weight(Openings.read(openBarred)), 1e-9)
        local closed = world:window(5, 3, 0, "N")
        assert.are.equal(0, Leak.weight(Openings.read(closed)))
        local frame = world:frame(3, 3, 0, "N", { barricades = { { metal = true } } })
        assert.near(0.85 * 0.05, Leak.weight(Openings.read(frame)), 1e-9)
        assert.are.equal(0, Leak.weight(Openings.read(world:frame(2, 3, 0, "N", { hasWindow = true }))))
    end)

    it("knows the outer wall and the room inside it", function()
        local outer = world:window(1, 0, 0, "N")
        assert.is_true(Openings.isExterior(outer, key))
        assert.are.equal("vanilla:1", Openings.interiorRoomKey(outer, key))
        local south = world:window(4, 3, 0, "N")
        assert.is_true(Openings.isExterior(south, key))
        assert.are.equal("vanilla:2", Openings.interiorRoomKey(south, key))
        local inner = world:door(3, 1, 0, "W")
        assert.is_false(Openings.isExterior(inner, key))
        assert.is_nil(Openings.interiorRoomKey(inner, key))
        assert.are.equal(inner, Openings.doorBetween(world:square(2, 1, 0), world:square(3, 1, 0)))
        assert.is_nil(Openings.doorBetween(world:square(2, 0, 0), world:square(3, 0, 0)))
    end)
end)
