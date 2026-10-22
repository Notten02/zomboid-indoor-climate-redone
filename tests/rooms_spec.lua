-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Room states: keys, unvisited buildings, catching up after a gap or a power cut, and stepping all rooms of a
-- building together.
local Config = require("IndoorClimateRedone/Config")
local Model = require("IndoorClimateRedone/Model")
local Leak = require("IndoorClimateRedone/Leak")
local Rooms = require("IndoorClimateRedone/Rooms")

local EPS = 1e-9

-- What one update saw, with defaults for the fields a test does not care about.
local function seen(fields)
    local w = { roomKey = "vanilla:1", kind = "vanilla", area = 77, rooms = {}, edges = {}, powered = false,
        nowHours = 10, outdoorC = 0, vanillaAirC = 0 }
    for k, v in pairs(fields or {}) do
        w[k] = v
    end
    return w
end

describe("Rooms keys", function()
    it("use the original mod's formats", function()
        assert.are.equal("building:x10630:y10260:w7:h11", Rooms.buildingKey(10630, 10260, 7, 11))
        assert.are.equal("building:42", Rooms.buildingIdKey(42))
        assert.are.equal("vanilla:123456", Rooms.vanillaRoomKey(123456))
        assert.are.equal("player:region:17:z1", Rooms.playerRoomKey(17, 1))
    end)
end)

describe("Rooms.newBuilding", function()
    it("starts 2 C above outdoor air, sealed, at the current hour", function()
        assert.are.same({ temperature = 7, lastWorldHour = 3, lastSeenHour = 3, lastPowered = true, leakScore = 0,
            openDoors = 0, openWindows = 0 }, Rooms.newBuilding(Config.defaults(), 5, 3, true))
    end)
end)

describe("Rooms.stepRoom", function()
    local config = Config.defaults()

    it("steps from the room's last hour with its leak score", function()
        local state = { temperature = 20, lastWorldHour = 8, leakScore = 1, lastPowered = false }
        assert.near(Model.step(config, 20, 2, false, 0, 0, 1), Rooms.stepRoom(config, state, false, 10, 0, 0), EPS)
    end)

    it("catches up on at most 168 hours", function()
        local state = { temperature = 20, lastWorldHour = 0, leakScore = 0 }
        assert.near(Model.step(config, 20, 168, false, 0, 0, 0), Rooms.stepRoom(config, state, false, 1000, 0, 0), EPS)
    end)

    it("steps the hours before a power cut powered and the hours after unpowered", function()
        local state = { temperature = 10, lastWorldHour = 0, leakScore = 0, lastPowered = true, lastVanillaAir = 21 }
        local before = Model.step(config, 10, 4, true, 0, 21, 0)
        local expected = Model.step(config, before, 6, false, 0, 0, 0)
        assert.near(expected, Rooms.stepRoom(config, state, false, 10, 0, 0, 4), EPS)
        assert.is_true(expected > Model.step(config, 10, 10, false, 0, 0, 0))
    end)

    it("ignores a power cut outside the stepped window", function()
        local state = { temperature = 10, lastWorldHour = 5, leakScore = 0, lastPowered = true }
        local plain = Model.step(config, 10, 5, false, 0, 0, 0)
        assert.near(plain, Rooms.stepRoom(config, state, false, 10, 0, 0, 3), EPS)
        assert.near(plain, Rooms.stepRoom(config, state, false, 10, 0, 0, 10), EPS)
        assert.near(plain, Rooms.stepRoom(config, state, false, 10, 0, 0, nil), EPS)
    end)

    it("ignores a power cut before the 168 hour window", function()
        local state = { temperature = 10, lastWorldHour = 0, leakScore = 0, lastPowered = true }
        assert.near(Model.step(config, 10, 168, false, 0, 0, 0), Rooms.stepRoom(config, state, false, 200, 0, 0, 20),
            EPS)
    end)

    it("ignores a power cut when the room was unpowered or power is back", function()
        local state = { temperature = 10, lastWorldHour = 0, leakScore = 0, lastPowered = false }
        assert.near(Model.step(config, 10, 10, false, 0, 0, 0), Rooms.stepRoom(config, state, false, 10, 0, 0, 4), EPS)
        state.lastPowered = true
        assert.near(Model.step(config, 10, 10, true, 0, 0, 0), Rooms.stepRoom(config, state, true, 10, 0, 0, 4), EPS)
    end)

    it("uses the powered target as vanilla air before the cut when none was saved", function()
        local state = { temperature = 10, lastWorldHour = 0, leakScore = 0, lastPowered = true }
        local before = Model.step(config, 10, 4, true, 0, 22, 0)
        assert.near(Model.step(config, before, 6, false, 0, 0, 0), Rooms.stepRoom(config, state, false, 10, 0, 0, 4),
            EPS)
    end)
end)

describe("Rooms.ensureRoom", function()
    it("creates a room from the building's values", function()
        local building = { temperature = 18, lastWorldHour = 4, lastSeenHour = 5, lastPowered = true,
            lastVanillaAir = 17 }
        local room = Rooms.ensureRoom(building, "vanilla:1", { area = 12, z = 1 }, 10, false, 3)
        assert.are.same({ temperature = 18, lastWorldHour = 4, lastSeenHour = 5, lastPowered = true,
            lastVanillaAir = 17, leakScore = 0, openDoors = 0, openWindows = 0, area = 12, z = 1 }, room)
        assert.are.equal(room, building.roomStates["vanilla:1"])
    end)

    it("fills what the building lacks from the update", function()
        local room = Rooms.ensureRoom({}, "vanilla:1", nil, 10, true, 3)
        assert.are.same({ temperature = 3, lastWorldHour = 10, lastSeenHour = 10, lastPowered = true,
            lastVanillaAir = 3, leakScore = 0, openDoors = 0, openWindows = 0, area = 1 }, room)
    end)

    it("keeps an existing room and updates its area from the scan", function()
        local building = { roomStates = { ["vanilla:1"] = { temperature = 5, area = 4, z = 0 } } }
        local room = Rooms.ensureRoom(building, "vanilla:1", { area = 9 }, 10, false, 3)
        assert.are.equal(5, room.temperature)
        assert.are.equal(9, room.area)
        assert.are.equal(0, room.z)
        assert.are.equal(9, Rooms.ensureRoom(building, "vanilla:1", nil, 10, false, 3).area)
    end)
end)

describe("Rooms.advanceBuilding", function()
    local config = Config.defaults()

    it("steps the looked-at room and copies it onto the building", function()
        local building = Rooms.newBuilding(config, 5, 0, false)
        local room = Rooms.advanceBuilding(config, building, seen({ nowHours = 10, outdoorC = 5, vanillaAirC = 5 }))
        assert.near(Model.step(config, 7, 10, false, 5, 5, 0), room.temperature, EPS)
        assert.are.equal(room.temperature, building.temperature)
        assert.are.equal(5, building.targetTemperature)
        assert.are.equal(10, building.lastWorldHour)
        assert.are.equal(10, building.lastSeenHour)
        assert.is_false(building.lastPowered)
        assert.are.equal("vanilla", building.kind)
        assert.are.equal(77, building.area)
        assert.are.equal(1, building.roomModelVersion)
    end)

    it("gives each room its own leaks", function()
        local building = Rooms.newBuilding(config, 0, 0, false)
        local leaks = Leak.summarize({ { kind = "door", open = true, roomKey = "vanilla:2" } })
        Rooms.advanceBuilding(config, building, seen({ leaks = leaks, rooms = { ["vanilla:1"] = { area = 10 },
            ["vanilla:2"] = { area = 10 } } }))
        local one, two = building.roomStates["vanilla:1"], building.roomStates["vanilla:2"]
        assert.are.equal(0, one.leakScore)
        assert.are.equal(1, two.leakScore)
        assert.are.equal(1, two.openDoors)
        assert.near(Model.step(config, 2, 10, false, 0, 0, 0), one.temperature, EPS)
        assert.near(Model.step(config, 2, 10, false, 0, 0, 1), two.temperature, EPS)
    end)

    it("gives the looked-at room the building's leaks when no opening belongs to a room", function()
        local building = Rooms.newBuilding(config, 0, 0, false)
        local room = Rooms.advanceBuilding(config, building, seen({ leaks = Leak.summarize({ { kind = "door",
            open = true } }) }))
        assert.are.equal(1, room.leakScore)
        assert.are.equal(1, building.openDoors)
    end)

    it("targets the leak-adjusted powered temperature with power", function()
        local building = Rooms.newBuilding(config, 0, 0, true)
        local leaks = Leak.summarize({ { kind = "window", open = true, roomKey = "vanilla:1" } })
        local room = Rooms.advanceBuilding(config, building, seen({ powered = true, outdoorC = -10, leaks = leaks }))
        assert.near(Model.poweredTarget(config, -10, 0.7), room.targetTemperature, EPS)
        assert.near(Model.step(config, -8, 10, true, -10, 0, 0.7), room.temperature, EPS)
    end)

    it("shares heat between joined rooms for the time since the building's last update", function()
        local building = { temperature = 0, lastWorldHour = 9, lastPowered = false, roomStates = {
            ["vanilla:1"] = { temperature = 30, lastWorldHour = 9, area = 10, leakScore = 0 },
            ["vanilla:2"] = { temperature = 10, lastWorldHour = 9, area = 30, leakScore = 0 },
        } }
        Rooms.advanceBuilding(config, building, seen({ outdoorC = 20, vanillaAirC = 20,
            rooms = { ["vanilla:1"] = { area = 10 }, ["vanilla:2"] = { area = 30 } },
            edges = { { a = "vanilla:1", b = "vanilla:2", passages = 1 } } }))
        local one = Model.step(config, 30, 1, false, 20, 20, 0)
        local two = Model.step(config, 10, 1, false, 20, 20, 0)
        local a, b = Model.exchange(one, two, 10, 30, 1, 3.0)
        assert.near(a, building.roomStates["vanilla:1"].temperature, EPS)
        assert.near(b, building.roomStates["vanilla:2"].temperature, EPS)
        assert.near(a, building.temperature, EPS)
    end)

    it("uses each edge's rate", function()
        local function run(edge)
            local building = { lastWorldHour = 9, roomStates = {
                ["vanilla:1"] = { temperature = 30, lastWorldHour = 9, area = 10 },
                ["vanilla:2"] = { temperature = 10, lastWorldHour = 9, area = 10 },
            } }
            edge.a, edge.b = "vanilla:1", "vanilla:2"
            Rooms.advanceBuilding(config, building, seen({ outdoorC = 20, vanillaAirC = 20, edges = { edge },
                rooms = { ["vanilla:1"] = { area = 10 }, ["vanilla:2"] = { area = 10 } } }))
            return building.roomStates["vanilla:1"].temperature
        end
        local closed, wall, none = run({ doors = 1 }), run({ walls = 1 }), run({})
        assert.is_true(closed < wall and wall < none)
    end)

    it("does not share heat without elapsed time", function()
        local building = { lastWorldHour = 10, roomStates = {
            ["vanilla:1"] = { temperature = 30, lastWorldHour = 10, area = 10 },
            ["vanilla:2"] = { temperature = 10, lastWorldHour = 10, area = 10 },
        } }
        Rooms.advanceBuilding(config, building, seen({ rooms = { ["vanilla:1"] = {}, ["vanilla:2"] = {} },
            edges = { { a = "vanilla:1", b = "vanilla:2", passages = 1 } } }))
        assert.are.equal(30, building.roomStates["vanilla:1"].temperature)
        assert.are.equal(10, building.roomStates["vanilla:2"].temperature)
    end)

    it("starts a room it has not seen before from the building's temperature and last hour", function()
        local building = { temperature = 15, lastWorldHour = 6, lastPowered = false }
        local room = Rooms.advanceBuilding(config, building, seen({ roomKey = "vanilla:5" }))
        assert.near(Model.step(config, 15, 4, false, 0, 0, 0), room.temperature, EPS)
    end)

    it("leaves rooms that neither the scan nor the update mention as they were", function()
        local stale = { temperature = 12, lastWorldHour = 1, area = 4 }
        local building = { lastWorldHour = 9, roomStates = { ["vanilla:7"] = stale } }
        Rooms.advanceBuilding(config, building, seen({}))
        assert.are.equal(12, stale.temperature)
        assert.are.equal(1, stale.lastWorldHour)
    end)

    it("splits a power cut per room", function()
        local building = Rooms.newBuilding(config, 0, 0, true)
        building.lastVanillaAir = 22
        Rooms.advanceBuilding(config, building, seen({ powered = true, nowHours = 1, vanillaAirC = 22 }))
        local before = building.temperature
        Rooms.advanceBuilding(config, building, seen({ powered = false, nowHours = 11, powerOffHour = 5 }))
        local expected = Model.step(config, Model.step(config, before, 4, true, 0, 22, 0), 6, false, 0, 0, 0)
        assert.near(expected, building.temperature, EPS)
    end)
end)

describe("Rooms.advanceZone", function()
    local config = Config.defaults()

    it("steps a single-room space with its leaks", function()
        local state = Rooms.newBuilding(config, 0, 0, false)
        Rooms.advanceZone(config, state, seen({ kind = "player", area = 20,
            leaks = { leakScore = 0.5, openDoors = 1, openWindows = 0 } }))
        assert.near(Model.step(config, 2, 10, false, 0, 0, 0.5), state.temperature, EPS)
        assert.are.equal(0.5, state.leakScore)
        assert.are.equal(1, state.openDoors)
        assert.are.equal(0, state.targetTemperature)
        assert.are.equal(10, state.lastWorldHour)
        assert.are.equal("player", state.kind)
        assert.are.equal(20, state.area)
    end)

    it("treats missing leaks as sealed", function()
        local state = Rooms.newBuilding(config, 0, 0, false)
        state.leakScore = 1
        Rooms.advanceZone(config, state, seen({}))
        assert.are.equal(0, state.leakScore)
    end)
end)
