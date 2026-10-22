-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Settings: the sandbox options keep the original mod's names, ranges and defaults, values are clamped to their
-- ranges, and sandbox-options.txt declares exactly the options Config reads.
local Config = require("IndoorClimateRedone/Config")

local SANDBOX = "Contents/mods/IndoorClimateRedone/42/media/sandbox-options.txt"

local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

-- { { namespace, name, fields = { key = value } }, ... } in file order.
local function parseSandboxOptions(text)
    local options = {}
    for namespace, name, body in text:gmatch("option%s+([%w_]+)%.([%w_]+)%s*(%b{})") do
        local fields = {}
        for key, value in body:gmatch("([%w_]+)%s*=%s*([^,\n]+),") do
            fields[key] = value:match("^%s*(.-)%s*$")
        end
        options[#options + 1] = { namespace = namespace, name = name, fields = fields }
    end
    return options
end

describe("Config", function()
    it("defaults to the original mod's values", function()
        local c = Config.defaults()
        assert.is_true(c.Enabled)
        assert.are.equal(1, c.UpdateMinutes)
        assert.are.equal(2.0, c.UnvisitedOffsetC)
        assert.are.equal(0.04, c.HeaterGeneratorFuelPerHour)
        assert.are.equal(22.0, c.PoweredTargetC)
        assert.are.equal(3.0, c.PoweredRatePerHour)
        assert.are.equal(0.75, c.PoweredLeakInfluence)
        assert.are.equal(0.06, c.SealedLossPerHour)
        assert.are.equal(12.0, c.BreachMultiplier)
        assert.are.equal(5, c.ScanRadius)
        assert.is_true(c.NativeBridge)
        assert.is_false(c.DebugLogging)
    end)

    it("adds the fixed tuning values", function()
        local c = Config.defaults()
        assert.are.equal(2.0, c.LocalHeatRatePerHour)
        assert.are.equal(168.0, c.MaxElapsedHours)
        assert.are.equal(300, c.EnvelopeScanBudget)
        assert.are.equal(1500, c.ServerScanBudget)
        assert.are.equal(6.0, c.EnvelopeRefreshHours)
        assert.are.equal(0.25, c.EnvelopeRetryHours)
        assert.are.equal(1024, c.MaxStoredZones)
        assert.are.equal(24, c.MaxEnvelopeCaches)
    end)

    it("reads the sandbox values", function()
        local c = Config.read({ Enabled = false, PoweredTargetC = 25.5, SealedLossPerHour = 0.1, DebugLogging = true })
        assert.is_false(c.Enabled)
        assert.are.equal(25.5, c.PoweredTargetC)
        assert.are.equal(0.1, c.SealedLossPerHour)
        assert.is_true(c.DebugLogging)
        assert.are.equal(12.0, c.BreachMultiplier)
    end)

    it("clamps every number to its range", function()
        for _, option in ipairs(Config.OPTIONS) do
            local name = option.name
            if option.type ~= "boolean" then
                assert.are.equal(option.min, Config.read({ [name] = option.min - 100 })[name], name)
                assert.are.equal(option.max, Config.read({ [name] = option.max + 100 })[name], name)
            end
        end
    end)

    it("rounds the integer options", function()
        assert.are.equal(8, Config.read({ UpdateMinutes = 7.5 }).UpdateMinutes)
        assert.are.equal(7, Config.read({ UpdateMinutes = 7.4 }).UpdateMinutes)
        assert.are.equal(3, Config.read({ ScanRadius = "2.6" }).ScanRadius)
    end)

    it("reads numeric strings and falls back to the default for anything else", function()
        assert.are.equal(24.0, Config.read({ PoweredTargetC = "24" }).PoweredTargetC)
        assert.are.equal(22.0, Config.read({ PoweredTargetC = "warm" }).PoweredTargetC)
        assert.are.equal(12.0, Config.read({ BreachMultiplier = {} }).BreachMultiplier)
    end)

    it("treats only true as true for a set boolean", function()
        assert.is_false(Config.read({ NativeBridge = "true" }).NativeBridge)
        assert.is_false(Config.read({ NativeBridge = 1 }).NativeBridge)
        assert.is_true(Config.read({ NativeBridge = true }).NativeBridge)
        assert.is_true(Config.read({}).NativeBridge)
    end)

    it("ignores a sandbox table that is not a table", function()
        assert.are.same(Config.defaults(), Config.read("broken"))
    end)

    it("returns a fresh table each time", function()
        local a = Config.defaults()
        a.PoweredTargetC = 99
        assert.are.equal(22.0, Config.defaults().PoweredTargetC)
    end)

    it("clamp turns a non-number into the minimum", function()
        assert.are.equal(0, Config.clamp(nil, 0, 1))
        assert.are.equal(0.5, Config.clamp("0.5", 0, 1))
    end)
end)

describe("sandbox-options.txt", function()
    local options = parseSandboxOptions(read(SANDBOX))

    it("declares the options Config reads, in the same order, under the original names", function()
        assert.are.equal(#Config.OPTIONS, #options)
        for i, option in ipairs(Config.OPTIONS) do
            assert.are.equal("IndoorClimateLite", options[i].namespace)
            assert.are.equal(option.name, options[i].name)
        end
    end)

    it("matches Config's types, ranges and defaults", function()
        for i, option in ipairs(Config.OPTIONS) do
            local fields = options[i].fields
            assert.are.equal(option.type, fields.type, option.name)
            if option.type == "boolean" then
                assert.are.equal(tostring(option.default), fields.default, option.name)
            else
                assert.are.equal(option.min, tonumber(fields.min), option.name)
                assert.are.equal(option.max, tonumber(fields.max), option.name)
                assert.are.equal(option.default, tonumber(fields.default), option.name)
            end
        end
    end)

    it("keeps the original pages and translation keys", function()
        for _, option in ipairs(options) do
            assert.are.equal("IndoorClimateLite_General", option.fields.page, option.name)
            assert.are.equal("IndoorClimateLite_" .. option.name, option.fields.translation, option.name)
        end
    end)
end)
