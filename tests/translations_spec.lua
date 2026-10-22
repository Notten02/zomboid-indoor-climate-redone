-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The English and Russian translations: the files are valid JSON with the same keys, and they hold every key the
-- code, the item scripts and the sandbox options use. The keys are the original mod's.
local FlatJson = require("support/flat_json")
local LuaSource = require("LuaSource")
local Heater = require("IndoorClimateRedone/Heater")

local MEDIA = "Contents/mods/IndoorClimateRedone/42/media/"
local LUA = MEDIA .. "lua/"
local TRANSLATE = LUA .. "shared/Translate/"
local LANGUAGES = { "EN", "RU" }
local FILES = { "ContextMenu", "ItemName", "Sandbox", "UI" }

local function files(dir)
    local found = {}
    local p = assert(io.popen('find "' .. dir .. '" -type f | sort'))
    for path in p:lines() do
        found[#found + 1] = path:sub(#dir + 1)
    end
    p:close()
    return found
end

-- lang -> file -> { map = key -> text, keys = keys in order }
local function load()
    local all = {}
    for _, lang in ipairs(LANGUAGES) do
        all[lang] = {}
        for _, name in ipairs(FILES) do
            local path = TRANSLATE .. lang .. "/" .. name .. ".json"
            local ok, map, keys = pcall(FlatJson.parse, LuaSource.read(path))
            assert(ok, path .. ": " .. tostring(map))
            all[lang][name] = { map = map, keys = keys }
        end
    end
    return all
end

describe("translations", function()
    local all = load()

    it("are the same files in every language, and nothing else", function()
        local expected = {}
        for _, name in ipairs(FILES) do
            expected[#expected + 1] = "/" .. name .. ".json"
        end
        table.sort(expected)
        for _, lang in ipairs(LANGUAGES) do
            assert.are.same(expected, files(TRANSLATE .. lang), lang)
        end
    end)

    it("have the same keys in every language, none of them empty", function()
        for _, name in ipairs(FILES) do
            local english = all.EN[name]
            for _, lang in ipairs(LANGUAGES) do
                local other = all[lang][name]
                assert.are.same(english.keys, other.keys, lang .. "/" .. name .. ".json")
                for _, key in ipairs(other.keys) do
                    assert.is_true(other.map[key]:find("%S") ~= nil, lang .. " " .. key .. " is empty")
                end
            end
        end
    end)

    it("have every ICL key the code names", function()
        local used = 0
        for _, path in ipairs(LuaSource.find(LUA)) do
            for key in LuaSource.read(path):gmatch('"((%a+)_ICL[%w_]*)"') do
                local file = key:match("^(%a+)_")
                for _, lang in ipairs(LANGUAGES) do
                    assert.is_not_nil(all[lang][file], path .. ": no " .. file .. ".json for " .. key)
                    assert.is_not_nil(all[lang][file].map[key], lang .. " lacks " .. key .. " (" .. path .. ")")
                end
                used = used + 1
            end
        end
        assert.is_true(used >= 16, "found only " .. used .. " keys in the code")
    end)

    it("match the English fallbacks in the code", function()
        local english = all.EN.ContextMenu.map
        for fullType, profile in pairs(Heater.PROFILES) do
            for _, part in ipairs({ "install", "turnOn", "turnOff" }) do
                assert.are.equal(english[profile[part .. "Key"]], profile[part .. "Text"], fullType .. " " .. part)
            end
        end
        local menu = LuaSource.read(LUA .. "client/IndoorClimateRedone/DeviceMenu.lua")
        local checked = 0
        for key, fallback in menu:gmatch('text%("(ContextMenu_[%w_]+)",%s*"([^"]*)"%)') do
            assert.are.equal(english[key], fallback, key)
            checked = checked + 1
        end
        assert.is_true(checked >= 7, "found only " .. checked .. " menu texts")
    end)

    it("keep the percent placeholder of the propane fill", function()
        for _, lang in ipairs(LANGUAGES) do
            local value = all[lang].ContextMenu.map.ContextMenu_ICLPropaneRemaining
            assert.truthy(value:find("%d%%", 1, true), lang)
            assert.truthy(string.format(value, 42):find("42%", 1, true), lang)
        end
    end)

    it("name every device item, in English as the item script does", function()
        local script = LuaSource.read(MEDIA .. "scripts/IndoorClimateRedone/indoorclimate_items.txt")
        local count = 0
        for name, body in script:gmatch("item%s+([%w_]+)%s*(%b{})") do
            local key = "IndoorClimateLite." .. name
            for _, lang in ipairs(LANGUAGES) do
                assert.is_not_nil(all[lang].ItemName.map[key], lang .. " lacks " .. key)
            end
            assert.are.equal(body:match("DisplayName%s*=%s*([^,\r\n]+),"), all.EN.ItemName.map[key], key)
            count = count + 1
        end
        assert.are.equal(4, count)
        assert.are.equal(4, #all.EN.ItemName.keys)
    end)

    it("have a name and a tooltip for every sandbox option and a name for its page, and nothing more", function()
        local wanted = { Sandbox_IndoorClimateLite = true }
        local options = LuaSource.read(MEDIA .. "sandbox-options.txt")
        for body in options:gmatch("option%s+[%w_.]+%s*(%b{})") do
            local translation = body:match("translation%s*=%s*([%w_]+)")
            wanted["Sandbox_" .. translation] = true
            wanted["Sandbox_" .. translation .. "_tooltip"] = true
            wanted["Sandbox_" .. body:match("page%s*=%s*([%w_]+)")] = true
        end
        local english = {}
        for _, key in ipairs(all.EN.Sandbox.keys) do
            english[key] = true
        end
        assert.are.same(wanted, english)
    end)
end)
