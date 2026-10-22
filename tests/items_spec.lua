-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The device items keep the original mod's module and item IDs, and every model, texture and icon their scripts
-- name is in the mod.
local Heater = require("IndoorClimateRedone/Heater")

local MOD = "Contents/mods/IndoorClimateRedone/"
local SCRIPTS = MOD .. "42/media/scripts/IndoorClimateRedone/"

local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

-- name -> { field = value } for every `kind name { ... }` block.
local function blocks(text, kind)
    local found = {}
    for name, body in text:gmatch(kind .. "%s+([%w_]+)%s*(%b{})") do
        local fields = {}
        for key, value in body:gmatch("([%w_]+)%s*=%s*([^,\r\n]+),") do
            fields[key] = value
        end
        found[name] = fields
    end
    return found
end

describe("device items", function()
    local itemsText = read(SCRIPTS .. "indoorclimate_items.txt")
    local items = blocks(itemsText, "item")
    local models = blocks(read(SCRIPTS .. "indoorclimate_models.txt"), "model")

    it("are in the IndoorClimateLite module under the original IDs", function()
        assert.truthy(itemsText:find("module IndoorClimateLite", 1, true))
        local names = {}
        for fullType in pairs(Heater.PROFILES) do
            local name = fullType:match("^IndoorClimateLite%.(.+)$")
            assert.is_not_nil(items[name], fullType)
            names[#names + 1] = name
        end
        table.sort(names)
        assert.are.same({ "ElectricHeater", "PremiumHeater", "PropaneHeater", "StandingFan" }, names)
    end)

    it("name models, meshes, textures and icons that exist", function()
        for name, item in pairs(items) do
            local model = item.WorldStaticModel:match("^IndoorClimateLite%.(.+)$")
            assert.is_not_nil(models[model], name .. " model " .. tostring(model))
            assert.are.equal(item.WorldStaticModel, item.StaticModel)
            assert.is_true(exists(MOD .. "common/media/textures/Item_" .. item.Icon .. ".png"), name .. " icon")
        end
        for name, model in pairs(models) do
            assert.is_true(exists(MOD .. "common/media/models_X/" .. model.mesh .. ".fbx"), name .. " mesh")
            assert.is_true(exists(MOD .. "common/media/textures/" .. model.texture .. ".png"), name .. " texture")
        end
    end)
end)
