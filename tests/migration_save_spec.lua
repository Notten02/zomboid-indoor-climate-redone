-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- tools/prepare-migration-save.sh: copies a save made with the original and switches the copy's mods.txt to this
-- mod, leaving the source alone.

local function sh(command)
    local p = assert(io.popen(command .. " 2>&1; echo \"exit=$?\""))
    local out = p:read("*a")
    p:close()
    return out, tonumber(out:match("exit=(%d+)%s*$"))
end

local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

describe("prepare-migration-save.sh", function()
    local sandbox

    local function run(args)
        return sh('SANDBOX_DIR="' .. sandbox .. '" tools/prepare-migration-save.sh ' .. args)
    end

    before_each(function()
        local out = sh("mktemp -d")
        sandbox = out:match("^(%S+)")
        sh('mkdir -p "' .. sandbox .. '/World"')
        write(sandbox .. "/World/map_t.bin", "data")
    end)

    after_each(function()
        sh('rm -rf "' .. sandbox .. '"')
    end)

    it("renames the original's entry in the copy only, keeping the line endings", function()
        local mods = "VERSION = 1,\r\nmods\r\n{\r\n    mod = \\ExtensiveHealthRedone,\r\n"
            .. "    mod = \\IndoorClimateLiteB42,\r\n}\r\n"
        write(sandbox .. "/World/mods.txt", mods)
        local out, code = run("World")
        assert.are.equal(0, code, out)
        assert.are.equal(mods, read(sandbox .. "/World/mods.txt"))
        assert.are.equal(mods:gsub("\\IndoorClimateLiteB42", "IndoorClimateRedone"),
            read(sandbox .. "/World-redone-migration/mods.txt"))
        assert.are.equal("data", read(sandbox .. "/World-redone-migration/map_t.bin"))
    end)

    it("lists the mod once when the save already has both", function()
        write(sandbox .. "/World/mods.txt", "mods\n{\n    mod = IndoorClimateRedone,\n    mod = IndoorClimateLiteB42,\n}\n")
        local _, code = run("World")
        assert.are.equal(0, code)
        assert.are.equal("mods\n{\n    mod = IndoorClimateRedone,\n}\n",
            read(sandbox .. "/World-redone-migration/mods.txt"))
    end)

    it("copies nothing on a dry run, and refuses a save without the original or an existing copy", function()
        write(sandbox .. "/World/mods.txt", "mods\n{\n    mod = IndoorClimateLiteB42,\n}\n")
        local out, code = run("--dry-run World")
        assert.are.equal(0, code)
        assert.truthy(out:find("+    mod = IndoorClimateRedone,", 1, true), out)
        assert.is_nil(io.open(sandbox .. "/World-redone-migration/mods.txt", "rb"))

        assert.are.equal(0, select(2, run("World")))
        assert.are.equal(1, select(2, run("World")))

        sh('mkdir -p "' .. sandbox .. '/Plain"')
        write(sandbox .. "/Plain/mods.txt", "mods\n{\n    mod = SomethingElse,\n}\n")
        assert.are.equal(1, select(2, run("Plain")))
        assert.are.equal(2, select(2, run("../World")))
    end)
end)
