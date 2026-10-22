-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The mod's identity and the credit to the original author.

local MOD = "Contents/mods/IndoorClimateRedone/"

local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function isDir(path)
    local p = assert(io.popen('test -d "' .. path .. '" && echo yes'))
    local out = p:read("*a")
    p:close()
    return out:find("yes") ~= nil
end

local function parseModInfo(text)
    local info = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key then
            assert.is_nil(info[key], "mod.info sets " .. key .. " twice")
            info[key] = value
        end
    end
    return info
end

describe("mod.info", function()
    local info = parseModInfo(read(MOD .. "42/mod.info"))

    it("has its own mod ID", function()
        assert.are.equal("IndoorClimateRedone", info.id)
        assert.are.equal("Indoor Climate Redone", info.name)
    end)

    it("targets Build 42.21 or later", function()
        assert.are.equal("42.21.0", info.versionMin)
    end)

    it("cannot be enabled together with the original", function()
        local ids = {}
        for id in (info.incompatible or ""):gmatch("[^,]+") do
            ids[id] = true
        end
        assert.is_true(ids["\\IndoorClimateLiteB42"], "incompatible lists \\IndoorClimateLiteB42")
        assert.is_true(ids["IndoorClimateLiteB42"], "incompatible lists IndoorClimateLiteB42")
    end)

    it("credits the original author", function()
        assert.truthy(info.author:find("Frozen_Heart", 1, true))
        assert.truthy(info.description:find("Frozen_Heart", 1, true))
        assert.truthy(info.description:find("original author", 1, true))
    end)

    it("names only files that exist", function()
        for _, key in ipairs({ "poster", "icon" }) do
            if info[key] then
                assert.truthy(io.open(MOD .. "42/" .. info[key], "rb"), key .. " file " .. info[key])
            end
        end
    end)

    it("has the common folder Build 42 requires", function()
        assert.is_true(isDir(MOD .. "common"))
    end)
end)

describe("licence and credit files", function()
    it("keep reused content out of the MIT licence", function()
        local license = read("LICENSE")
        assert.truthy(license:find("MIT License", 1, true))
        assert.truthy(license:find("Frozen_Heart", 1, true))
        assert.truthy(license:find("ASSETS.md", 1, true))
    end)

    it("credit the original author and quote their permission", function()
        local assets = read("ASSETS.md")
        assert.truthy(assets:find("Frozen_Heart", 1, true))
        assert.truthy(assets:find("3772549209", 1, true))
        assert.truthy(assets:find("credit me as the original", 1, true))
    end)
end)

-- Width, height and size in bytes of a PNG file.
local function pngSize(path)
    local data = read(path)
    assert.are.equal("\137PNG\r\n\26\n", data:sub(1, 8), path .. " is not a PNG")
    local function u32(at)
        local a, b, c, d = data:byte(at, at + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return u32(17), u32(21), #data
end

describe("release art (tools/make-release-art.py)", function()
    it("has the icon and poster mod.info names", function()
        local info = parseModInfo(read(MOD .. "42/mod.info"))
        assert.are.equal("icon.png", info.icon)
        assert.are.equal("poster.png", info.poster)
        local w, h = pngSize(MOD .. "42/icon.png")
        assert.are.same({ 256, 256 }, { w, h })
        w, h = pngSize(MOD .. "42/poster.png")
        assert.are.same({ 512, 512 }, { w, h })
    end)

    it("has a Workshop preview the in-game uploader accepts: 256x256, at most 1000 KB", function()
        local w, h, bytes = pngSize("preview.png")
        assert.are.same({ 256, 256 }, { w, h })
        assert.is_true(bytes <= 1000 * 1000)
    end)
end)
