-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- World data: versioning, zone lookup, pruning, the power record and taking over the original mod's saved rooms.
local Store = require("IndoorClimateRedone/Store")

describe("Store.open", function()
    it("sets up a world that never ran the mod", function()
        local data = {}
        assert.are.equal("new", Store.open(data, 12))
        assert.are.same({ version = Store.VERSION, createdHour = 12, zones = {}, power = {} }, data)
    end)

    it("keeps the zones of a world it ran in before", function()
        local data = { version = Store.VERSION, createdHour = 1, zones = { a = { temperature = 5 } }, power = {} }
        assert.are.equal("loaded", Store.open(data, 50))
        assert.are.equal(5, data.zones.a.temperature)
        assert.are.equal(1, data.createdHour)
    end)

    it("starts over on a version it does not know", function()
        local data = { version = 99, zones = { a = {} } }
        assert.are.equal("reset", Store.open(data, 3))
        assert.are.same({}, data.zones)
        assert.are.equal(Store.VERSION, data.version)
    end)

    it("repairs missing tables", function()
        local data = { version = Store.VERSION, zones = "junk" }
        Store.open(data, 0)
        assert.are.same({}, data.zones)
        assert.are.same({}, data.power)
    end)
end)

describe("Store.zone", function()
    it("finds a zone by its key", function()
        local data = { zones = { ["building:1"] = { temperature = 3 } } }
        assert.are.equal(3, Store.zone(data, { key = "building:1" }).temperature)
        assert.is_nil(Store.zone(data, { key = "building:2" }))
    end)

    it("moves a state saved under the room's key to the building's", function()
        local old = { temperature = 8 }
        local data = { zones = { ["vanilla:4"] = old } }
        assert.are.equal(old, Store.zone(data, { key = "building:1", legacyKey = "vanilla:4" }))
        assert.are.equal(old, data.zones["building:1"])
        assert.is_nil(data.zones["vanilla:4"])
    end)
end)

describe("Store.prune", function()
    it("drops the least recently seen zones beyond the limit, never a kept one", function()
        local data = { zones = { a = { lastSeenHour = 1 }, b = { lastSeenHour = 2 }, c = { lastSeenHour = 3 },
            d = { lastSeenHour = 4 } } }
        assert.are.equal(2, Store.prune(data, 1, { a = true }))
        assert.are.same({ a = { lastSeenHour = 1 }, d = { lastSeenHour = 4 } }, data.zones)
        assert.are.equal(0, Store.prune(data, 5, {}))
    end)
end)

describe("Store.trackPower", function()
    it("remembers when the grid went off until it comes back", function()
        local data = { power = {} }
        Store.trackPower(data, true, 1)
        assert.is_nil(data.power.offHour)
        Store.trackPower(data, false, 5)
        assert.are.equal(5, data.power.offHour)
        Store.trackPower(data, false, 6)
        assert.are.equal(5, data.power.offHour)
        assert.are.equal(6, data.power.lastSeenHour)
        Store.trackPower(data, true, 7)
        assert.is_nil(data.power.offHour)
        assert.is_true(data.power.on)
    end)
end)

describe("Store.importOriginal", function()
    it("takes over map building states the original saved, not player-built rooms", function()
        local data = { zones = { ["building:x1:y1:w1:h1"] = { temperature = 1 } } }
        local old = { version = 1, power = { on = true }, rooms = {
            ["building:x1:y1:w1:h1"] = { temperature = 99 },
            ["building:x5:y5:w2:h2"] = { temperature = 18.5, lastWorldHour = 40, lastPowered = true, kind = "vanilla",
                junk = "x",
                roomStates = { ["vanilla:7"] = { temperature = 19, area = 4 }, bad = { temperature = 1 } } },
            ["vanilla:3"] = { temperature = 12 },
            ["player:region:5:z0"] = { temperature = 30 },
            ["building:broken"] = { temperature = "warm" },
        } }
        assert.are.equal(2, Store.importOriginal(data, old))
        assert.are.equal(1, data.zones["building:x1:y1:w1:h1"].temperature)
        local imported = data.zones["building:x5:y5:w2:h2"]
        assert.are.equal(18.5, imported.temperature)
        assert.are.equal(40, imported.lastWorldHour)
        assert.is_true(imported.lastPowered)
        assert.are.equal("vanilla", imported.kind)
        assert.is_nil(imported.junk)
        assert.are.same({ ["vanilla:7"] = { temperature = 19, area = 4 } }, imported.roomStates)
        assert.are.equal(12, data.zones["vanilla:3"].temperature)
        assert.is_nil(data.zones["player:region:5:z0"])
        assert.is_nil(data.zones["building:broken"])
    end)

    it("ignores missing or malformed data", function()
        local data = { zones = {} }
        assert.are.equal(0, Store.importOriginal(data, nil))
        assert.are.equal(0, Store.importOriginal(data, { rooms = "x" }))
    end)
end)
