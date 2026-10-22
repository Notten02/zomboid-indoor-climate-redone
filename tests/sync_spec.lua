-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- When the server sends a player's sample (Sync): first sample, changes beyond the thresholds, the heartbeat, the
-- clear when the player leaves, and the command arguments.
local Sync = require("IndoorClimateRedone/Sync")

local function sample(fields)
    local s = { airC = 18, baseRoomC = 18, targetC = 10, vanillaAirC = 10, outdoorC = 10, roomKey = "vanilla:1",
        buildingKey = "building:x0:y0:w4:h4", roomKind = "vanilla", indoors = true, powered = false, leakScore = 0,
        openDoors = 0, openWindows = 0, envelopeComplete = true }
    for name, value in pairs(fields or {}) do
        s[name] = value
    end
    return s
end

describe("Sync", function()
    it("sends the first sample, and nothing for a player who has none", function()
        local command, record = Sync.next(nil, sample(), 0)
        assert.are.equal(Sync.SAMPLE, command)
        assert.is_not_nil(record.sent)
        command, record = Sync.next(nil, nil, 0)
        assert.is_nil(command)
        assert.is_false(record.sent)
    end)

    it("does not send the same sample again before the heartbeat", function()
        local s = sample()
        local _, record = Sync.next(nil, s, 0)
        local command = Sync.next(record, s, Sync.HEARTBEAT_MS - 1)
        assert.is_nil(command)
    end)

    it("sends a temperature that moved by 0.2 C since the last send, adding up small steps", function()
        local _, record = Sync.next(nil, sample(), 0)
        local command
        command, record = Sync.next(record, sample({ airC = 18.1 }), 1000)
        assert.is_nil(command)
        command, record = Sync.next(record, sample({ airC = 18.19 }), 2000)
        assert.is_nil(command)
        command, record = Sync.next(record, sample({ airC = 18.21 }), 3000)
        assert.are.equal(Sync.SAMPLE, command)
        assert.are.equal(18.21, record.sent.airC)
        for _, name in ipairs(Sync.TEMPERATURES) do
            local _, fresh = Sync.next(nil, sample(), 0)
            assert.are.equal(Sync.SAMPLE, (Sync.next(fresh, sample({ [name] = 25 }), 1)), name)
        end
    end)

    it("sends another room, power, doors, windows, devices in reach and leaks at once", function()
        local changes = { { roomKey = "vanilla:2" }, { buildingKey = "building:other" }, { powered = true },
            { openDoors = 1 }, { openWindows = 2 }, { indoors = false }, { roomKind = "player" },
            { envelopeComplete = false }, { leakScore = 0.01 }, { heaterCount = 1 } }
        for _, change in ipairs(changes) do
            local _, record = Sync.next(nil, sample(), 0)
            local command = Sync.next(record, sample(change), 1)
            assert.are.equal(Sync.SAMPLE, command)
        end
        local _, record = Sync.next(nil, sample(), 0)
        assert.is_nil((Sync.next(record, sample({ leakScore = 0.005 }), 1)))
    end)

    it("sends the sample again after the heartbeat", function()
        local s = sample()
        local _, record = Sync.next(nil, s, 0)
        assert.are.equal(Sync.SAMPLE, (Sync.next(record, s, Sync.HEARTBEAT_MS)))
    end)

    it("clears once when the player leaves, and sends again when they come back", function()
        local _, record = Sync.next(nil, sample(), 0)
        local command
        command, record = Sync.next(record, nil, 10)
        assert.are.equal(Sync.CLEAR, command)
        command, record = Sync.next(record, nil, Sync.HEARTBEAT_MS * 3)
        assert.is_nil(command)
        command = Sync.next(record, sample(), Sync.HEARTBEAT_MS * 3)
        assert.are.equal(Sync.SAMPLE, command)
    end)

    it("packs the plain fields with the player's ID and unpacks them", function()
        local s = sample({ extra = { nested = true }, fn = function() end })
        local args = Sync.pack(s, 7)
        assert.are.equal(7, args.playerId)
        assert.is_nil(args.extra)
        assert.is_nil(args.fn)
        local back = assert(Sync.unpack(args))
        assert.is_nil(back.playerId)
        s.extra, s.fn = nil, nil
        assert.are.same(s, back)
        assert.is_nil(Sync.unpack({ playerId = 7 }))
        assert.is_nil(Sync.unpack(nil))
    end)
end)
