-- LuaLS's bundled luassert definitions omit the optional failure-message argument; the game stand-ins are partial.
---@diagnostic disable: redundant-parameter, missing-fields, duplicate-set-field
-- Where the devices are found: the container lists and the extra roll in warehouses and storage units, with the
-- original mod's weights.
local FakeGame = require("support/fake_game")
local FakeWorld = require("support/fake_world")

local STANDARD = "IndoorClimateLite.ElectricHeater"
local PREMIUM = "IndoorClimateLite.PremiumHeater"
local FAN = "IndoorClimateLite.StandingFan"
local PROPANE = "IndoorClimateLite.PropaneHeater"

local NAMES = { "ElectronicStoreAppliances", "GigamartHouseElectronics", "GigamartHousewares", "GarageTools",
    "GarageMechanics", "ClosetShelfGeneric", "CrateCamping", "CampingStoreGear", "CampingStoreTools" }

-- Loads Loot.lua the way the game does, with vanilla's lists stood in for. Returns the game, world, lists and Loot.
local function load(opts)
    opts = opts or {}
    local game = FakeGame.install({ server = true })
    local world = FakeWorld.install(game)
    local lists = {}
    for _, name in ipairs(NAMES) do
        lists[name] = { items = { "Base.Hammer", 4 } }
    end
    lists.ElectronicStoreAppliances.items = { STANDARD, 99, "Base.Radio", 3 }
    package.preload["Items/ProceduralDistributions"] = function()
        _G.ProceduralDistributions = { list = lists }
        return true
    end
    package.loaded["Items/ProceduralDistributions"] = nil
    package.loaded["IndoorClimateRedone/Loot"] = nil
    _G.ItemPickerJava = { getLootModifier = function() return opts.modifier or 1 end }
    local Loot = require("IndoorClimateRedone/Loot")
    return game, world, lists, Loot
end

local function weight(items, itemType)
    for index = 1, #items, 2 do
        if items[index] == itemType then
            return items[index + 1]
        end
    end
    return nil
end

insulate("loot lists", function()
    it("add the devices with the original weights, replacing a weight already there", function()
        local _, _, lists = load()
        assert.are.same({ STANDARD, 18, "Base.Radio", 3, PREMIUM, 7, FAN, 18, PROPANE, 4 },
            lists.ElectronicStoreAppliances.items)
        assert.are.same({ "Base.Hammer", 4, STANDARD, 2, PREMIUM, 0.35, FAN, 2, PROPANE, 2 },
            lists.GarageTools.items)
        assert.are.equal(0.4, weight(lists.ClosetShelfGeneric.items, STANDARD))
        assert.are.equal(0.08, weight(lists.ClosetShelfGeneric.items, PREMIUM))
        assert.are.equal(0.05, weight(lists.ClosetShelfGeneric.items, PROPANE))
        assert.are.equal(2, weight(lists.CrateCamping.items, PROPANE))
        assert.is_nil(weight(lists.CrateCamping.items, STANDARD))
        -- CratePropane is not in this stand-in: left alone.
        assert.is_nil(lists.CratePropane)
    end)
end)

insulate("warehouse and storage unit containers", function()
    local function container(world, kind)
        local box = world:container()
        box.type = kind or "crate"
        box.square = world:square(0, 0, 0) or world:ensureSquare(0, 0, 0)
        return box
    end

    it("roll after the game's loot: the room's weights in percent, times the other-loot multiplier", function()
        local game, world, _, Loot = load()
        assert.are.equal(1, #game.events.OnFillContainer.handlers)
        local rolls = {}
        _G.ZombRand = function(max)
            rolls[#rolls + 1] = max
            return table.remove(Loot.testRolls, 1)
        end
        local box = container(world)
        box:AddItem("Base.Hammer")
        -- Pick 7.5 of 15: past the cheap heater (5) and the premium (2), into the fan. Chance roll 1499 < 1500.
        Loot.testRolls = { 7500, 1499 }
        assert.is_true(Loot.fillRoomContainer("warehouse", "crate", box))
        assert.are.same({ 15000, 10000 }, rolls)
        assert.are.same({ "Base.Hammer", FAN }, { box.items[1].fullType, box.items[2].fullType })
        Loot.testRolls = { 0, 1500 }
        assert.is_false(Loot.fillRoomContainer("warehouse", "crate", box))
        -- A storage unit: 17%.
        Loot.testRolls = { 16999, 1699 }
        assert.is_true(Loot.fillRoomContainer("StorageUnit", "", box))
        assert.are.equal(PROPANE, box.items[3].fullType)
    end)

    it("scale with the other-loot multiplier, at most five times", function()
        local _, world, _, Loot = load({ modifier = 9 })
        assert.are.equal(5, Loot.multiplier())
        _G.ZombRand = function() return table.remove(Loot.testRolls, 1) end
        Loot.testRolls = { 0, 7499 }
        assert.is_true(Loot.fillRoomContainer("warehouse", "crate", container(world)))
        Loot.testRolls = { 0, 7500 }
        assert.is_false(Loot.fillRoomContainer("warehouse", "crate", container(world)))
        _G.ItemPickerJava = { getLootModifier = function() return 0 end }
        Loot.testRolls = { 0, 0 }
        assert.is_false(Loot.fillRoomContainer("warehouse", "crate", container(world)))
    end)

    it("leave other rooms, bodies, kitchen appliances and container descriptions alone", function()
        local _, world, _, Loot = load({ modifier = 5 })
        _G.ZombRand = function() return 0 end
        assert.is_false(Loot.fillRoomContainer("kitchen", "crate", container(world)))
        assert.is_false(Loot.fillRoomContainer("warehouse", "fridge", container(world)))
        assert.is_false(Loot.fillRoomContainer("warehouse", nil, container(world, "ZombieInventory")))
        assert.is_false(Loot.fillRoomContainer("warehouse", "crate", { getType = function() return "crate" end }))
        local nowhere = container(world)
        nowhere.square = nil
        assert.is_false(Loot.fillRoomContainer("warehouse", "crate", nowhere))
        assert.is_true(Loot.fillRoomContainer("warehouse", "crate", container(world)))
    end)
end)
