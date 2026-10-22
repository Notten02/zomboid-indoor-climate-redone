-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Every tracked text file is written for people who never saw how the mod was built: no project-planning vocabulary,
-- no references to private working notes. This catches the obvious slips; it is not the whole rule (see CLAUDE.md).

-- Lower-case Lua patterns. `except` lists files where the word is legitimate.
local BANNED = {
    { pattern = "phase%s*%d", what = "a planning phase number" },
    { pattern = "brainstorm", what = "planning vocabulary" },
    { pattern = "maintainer", what = "planning vocabulary" },
    { pattern = "spike", what = "planning vocabulary" },
    { pattern = "[^%w_%-]%.ai/", what = "a link to the private working notes", except = { ["./.gitignore"] = true } },
}

-- Files that state the rule itself.
local SKIP = {
    ["./CLAUDE.md"] = true,
    ["./tests/docs_spec.lua"] = true,
}

local BINARY = { png = true, jpg = true, fbx = true, ogg = true, wav = true, x = true }

local function textFiles()
    local files = {}
    local p = assert(io.popen("find . \\( -path ./.git -o -path ./.ai -o -path ./.cache \\) -prune -o -type f -print"
        .. " | sort"))
    for path in p:lines() do
        local ext = path:match("%.([%w]+)$")
        if not SKIP[path] and not (ext and BINARY[ext:lower()]) then
            files[#files + 1] = path
        end
    end
    p:close()
    return files
end

local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

describe("tracked text", function()
    local files = textFiles()

    it("is found", function()
        assert.is_true(#files > 10, "only " .. #files .. " files found; run the specs from the repo root")
    end)

    it("has no planning vocabulary or links to working notes", function()
        local problems = {}
        for _, path in ipairs(files) do
            local lineNo = 0
            for line in (read(path) .. "\n"):gmatch("(.-)\n") do
                lineNo = lineNo + 1
                local lower = " " .. line:lower()
                for _, rule in ipairs(BANNED) do
                    if not (rule.except and rule.except[path]) and lower:find(rule.pattern) then
                        problems[#problems + 1] = string.format("%s:%d: %s", path, lineNo, rule.what)
                    end
                end
            end
        end
        assert.are.same({}, problems)
    end)

    it("has Markdown links to files and folders that exist", function()
        local problems = {}
        for _, path in ipairs(files) do
            if path:match("%.md$") then
                local dir = path:match("^(.*)/[^/]*$")
                for target in read(path):gmatch("%]%(([^)%s]+)%)") do
                    target = target:gsub("#.*$", "")
                    if target ~= "" and not target:find("^%a[%w+.-]*:") then
                        local ok = os.execute('test -e "' .. dir .. "/" .. target .. '"')
                        if ok ~= 0 and ok ~= true then
                            problems[#problems + 1] = path .. ": " .. target
                        end
                    end
                end
            end
        end
        assert.are.same({}, problems)
    end)
end)
