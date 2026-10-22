-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Leaks through the outer wall and heat exchange between rooms, with the original mod's weights.
local Leak = require("IndoorClimateRedone/Leak")

local EPS = 1e-9

local function door(open, roomKey)
    return { kind = "door", open = open, roomKey = roomKey }
end

local function window(fields)
    fields.kind = "window"
    return fields
end

describe("Leak.weight", function()
    it("counts an open door fully and a closed one not at all", function()
        assert.are.equal(1.0, Leak.weight(door(true)))
        assert.are.equal(0, Leak.weight(door(false)))
    end)

    it("ignores barricades on doors", function()
        local d = door(true)
        d.barricades = { { planks = 4 } }
        assert.are.equal(1.0, Leak.weight(d))
    end)

    it("weighs windows: smashed or glassless 0.85, open 0.70, closed 0", function()
        assert.near(0.85, Leak.weight(window({ smashed = true })), EPS)
        assert.near(0.85, Leak.weight(window({ glassRemoved = true })), EPS)
        assert.near(0.85, Leak.weight(window({ smashed = true, open = true })), EPS)
        assert.near(0.70, Leak.weight(window({ open = true })), EPS)
        assert.are.equal(0, Leak.weight(window({})))
    end)

    it("weighs an empty frame 0.85 and a frame holding a window 0", function()
        assert.near(0.85, Leak.weight({ kind = "windowFrame" }), EPS)
        assert.are.equal(0, Leak.weight({ kind = "windowFrame", hasWindow = true }))
    end)

    it("scales by the barricades on both sides", function()
        assert.near(0.70 * 0.60, Leak.weight(window({ open = true, barricades = { { planks = 1 } } })), EPS)
        assert.near(0.85 * 0.12, Leak.weight(window({ smashed = true, barricades = { nil, { planks = 4 } } })), EPS)
        assert.near(0.85 * 0.05 * 0.30,
            Leak.weight({ kind = "windowFrame", barricades = { { metal = true }, { metalBar = true } } }), EPS)
    end)

    it("is 0 for anything else", function()
        assert.are.equal(0, Leak.weight({ kind = "wall", open = true }))
        assert.are.equal(0, Leak.weight(nil))
    end)
end)

describe("Leak.barricadeFactor", function()
    it("follows the plank count", function()
        assert.are.equal(1.0, Leak.barricadeFactor({ planks = 0 }))
        assert.are.equal(0.60, Leak.barricadeFactor({ planks = 1 }))
        assert.are.equal(0.40, Leak.barricadeFactor({ planks = 2 }))
        assert.are.equal(0.25, Leak.barricadeFactor({ planks = 3 }))
        assert.are.equal(0.12, Leak.barricadeFactor({ planks = 4 }))
        assert.are.equal(0.12, Leak.barricadeFactor({ planks = 9 }))
        assert.are.equal(0.40, Leak.barricadeFactor({ planks = 2.7 }))
    end)

    it("puts metal bars before a metal sheet before planks", function()
        assert.are.equal(0.30, Leak.barricadeFactor({ metalBar = true, metal = true, planks = 4 }))
        assert.are.equal(0.05, Leak.barricadeFactor({ metal = true, planks = 4 }))
    end)

    it("is 1 without a barricade", function()
        assert.are.equal(1.0, Leak.barricadeFactor(nil))
    end)
end)

describe("Leak.summarize", function()
    it("adds the weights per room and for the building, capped at 1", function()
        local s = Leak.summarize({
            door(true, "vanilla:1"),
            window({ open = true, roomKey = "vanilla:1" }),
            window({ open = true, roomKey = "vanilla:2" }),
            door(false, "vanilla:2"),
        })
        assert.are.equal(1, s.leakScore)
        assert.are.equal(1, s.openDoors)
        assert.are.equal(2, s.openWindows)
        assert.near(1.70, s.perRoom["vanilla:1"].leakUnits, EPS)
        assert.are.equal(1, s.perRoom["vanilla:1"].leakScore)
        assert.are.equal(1, s.perRoom["vanilla:1"].openDoors)
        assert.are.equal(1, s.perRoom["vanilla:1"].openWindows)
        assert.near(0.70, s.perRoom["vanilla:2"].leakScore, EPS)
        assert.are.equal(0, s.perRoom["vanilla:2"].openDoors)
    end)

    it("counts frames as windows", function()
        assert.are.equal(1, Leak.summarize({ { kind = "windowFrame" } }).openWindows)
    end)

    it("counts openings without a room for the building only", function()
        local s = Leak.summarize({ door(true) })
        assert.are.equal(1, s.leakScore)
        assert.are.same({}, s.perRoom)
    end)

    it("is sealed without open openings", function()
        assert.are.same({ leakScore = 0, openDoors = 0, openWindows = 0, perRoom = {} },
            Leak.summarize({ door(false, "vanilla:1") }))
        assert.are.same({ leakScore = 0, openDoors = 0, openWindows = 0, perRoom = {} }, Leak.summarize(nil))
    end)
end)

describe("Leak.forRoom", function()
    it("returns the room's own leaks", function()
        local s = Leak.summarize({ window({ open = true, roomKey = "vanilla:2" }), door(true, "vanilla:1") })
        assert.near(0.70, Leak.forRoom(s, "vanilla:2").leakScore, EPS)
    end)

    it("returns no leaks for a sealed room in a leaking building", function()
        local s = Leak.summarize({ door(true, "vanilla:1") })
        assert.are.same({ leakScore = 0, openDoors = 0, openWindows = 0 }, Leak.forRoom(s, "vanilla:3"))
    end)

    it("uses the building's leaks when no opening belongs to a room, and stores them for the room", function()
        local s = Leak.summarize({ door(true) })
        local room = Leak.forRoom(s, "vanilla:3")
        assert.are.same({ leakScore = 1, openDoors = 1, openWindows = 0 }, room)
        assert.are.equal(room, s.perRoom["vanilla:3"])
    end)
end)

describe("Leak.mergeNearby", function()
    it("raises the building and the room to the leaks found near the player", function()
        local s = Leak.summarize({ window({ open = true, roomKey = "vanilla:1" }) })
        Leak.mergeNearby(s, "vanilla:1", { leakScore = 1, openDoors = 1, openWindows = 0 })
        assert.are.equal(1, s.leakScore)
        assert.are.equal(1, s.openDoors)
        assert.are.equal(1, s.openWindows)
        assert.are.equal(1, s.perRoom["vanilla:1"].leakScore)
        assert.are.equal(1, s.perRoom["vanilla:1"].openWindows)
    end)

    it("never lowers what the scan found", function()
        local s = Leak.summarize({ door(true, "vanilla:1") })
        Leak.mergeNearby(s, "vanilla:1", { leakScore = 0.2, openDoors = 0, openWindows = 0 })
        assert.are.equal(1, s.perRoom["vanilla:1"].leakScore)
    end)

    it("adds an entry for a room the scan has not reached", function()
        local s = Leak.summarize({})
        Leak.mergeNearby(s, "vanilla:9", { leakScore = 0.7, openDoors = 0, openWindows = 1 })
        assert.are.same({ leakScore = 0.7, openDoors = 0, openWindows = 1 }, s.perRoom["vanilla:9"])
    end)
end)

describe("Leak.edgeRate", function()
    it("joins rooms fully through a passage or an open door", function()
        assert.are.equal(3.0, Leak.edgeRate({ passages = 2, walls = 5 }))
        assert.are.equal(3.0, Leak.edgeRate({ doors = 1, openDoors = 1 }))
    end)

    it("joins rooms a little through a closed door, more through a walked link, barely through a wall", function()
        assert.are.equal(0.10, Leak.edgeRate({ doors = 1, openDoors = 0, learned = true, walls = 3 }))
        assert.are.equal(0.80, Leak.edgeRate({ learned = true, walls = 3 }))
        assert.are.equal(0.02, Leak.edgeRate({ walls = 3 }))
    end)

    it("is 0 for nothing", function()
        assert.are.equal(0, Leak.edgeRate({}))
        assert.are.equal(0, Leak.edgeRate(nil))
    end)
end)
