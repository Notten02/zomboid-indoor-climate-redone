-- Reads the game's translation files: one JSON object whose values are all strings. Strict, so a stray comma or a
-- missing quote fails the spec instead of the game quietly dropping the file.
--
--   local map, keys = FlatJson.parse(text)   -- key -> value, and the keys in file order; errors on bad JSON
local FlatJson = {}

local ESCAPES = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function fail(text, at, what)
    local line = select(2, text:sub(1, at):gsub("\n", "")) + 1
    error(string.format("line %d: %s", line, what), 0)
end

local function skip(text, at)
    return text:find("[^ \t\r\n]", at) or #text + 1
end

local function readString(text, at)
    if text:sub(at, at) ~= '"' then
        fail(text, at, "a string was expected")
    end
    local out = {}
    local i = at + 1
    while i <= #text do
        local c = text:sub(i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local e = text:sub(i + 1, i + 1)
            if ESCAPES[e] then
                out[#out + 1] = ESCAPES[e]
                i = i + 2
            elseif e == "u" and text:sub(i + 2, i + 5):match("^%x%x%x%x$") then
                out[#out + 1] = "\\u" .. text:sub(i + 2, i + 5)
                i = i + 6
            else
                fail(text, i, "a bad escape")
            end
        elseif c == "\n" or c:byte() < 32 then
            fail(text, i, "a control character in a string")
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    fail(text, at, "an unterminated string")
end

function FlatJson.parse(text)
    -- A UTF-8 byte order mark is allowed.
    local i = skip(text, text:sub(1, 3) == "\239\187\191" and 4 or 1)
    if text:sub(i, i) ~= "{" then
        fail(text, i, "the file must start with {")
    end
    local map, keys = {}, {}
    i = skip(text, i + 1)
    if text:sub(i, i) == "}" then
        i = i + 1
    else
        while true do
            local key, value
            key, i = readString(text, i)
            i = skip(text, i)
            if text:sub(i, i) ~= ":" then
                fail(text, i, "a : was expected after " .. key)
            end
            value, i = readString(text, skip(text, i + 1))
            if map[key] ~= nil then
                fail(text, i, "a duplicate key " .. key)
            end
            map[key] = value
            keys[#keys + 1] = key
            i = skip(text, i)
            local c = text:sub(i, i)
            if c == "}" then
                i = i + 1
                break
            elseif c ~= "," then
                fail(text, i, "a , or } was expected after " .. key)
            end
            i = skip(text, i + 1)
        end
    end
    if skip(text, i) <= #text then
        fail(text, i, "text after the closing }")
    end
    return map, keys
end

return FlatJson
