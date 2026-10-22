-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The offline stand-in for the game globals (tests/support/fake_game.lua) behaves as the specs that use it expect.
local FakeGame = require("support/fake_game")

insulate("FakeGame", function()
    it("runs as single player unless asked otherwise", function()
        FakeGame.install()
        assert.is_false(isServer())
        assert.is_false(isClient())
        FakeGame.install({ server = true })
        assert.is_true(isServer())
    end)

    it("fires events in order and removes handlers", function()
        local game = FakeGame.install()
        local seen = {}
        local function second() seen[#seen + 1] = "second" end
        game.events.OnGameStart.Add(function() seen[#seen + 1] = "first" end)
        game.events.OnGameStart.Add(second)
        game.events.OnGameStart.trigger()
        game.events.OnGameStart.Remove(second)
        game.events.OnGameStart.trigger()
        assert.are.same({ "first", "second", "first" }, seen)
    end)

    it("advances time with the minute events", function()
        local game = FakeGame.install()
        local ticks, minutes, tens = 0, 0, 0
        game.events.OnTick.Add(function() ticks = ticks + 1 end)
        game.events.EveryOneMinute.Add(function() minutes = minutes + 1 end)
        game.events.EveryTenMinutes.Add(function() tens = tens + 1 end)
        game.advance(20)
        assert.are.equal(200, ticks)
        assert.are.equal(20, minutes)
        assert.are.equal(2, tens)
        assert.is.near(6020 / 60, getGameTime():getWorldAgeHours(), 1e-6)
    end)

    it("keeps global ModData and records commands sent to players", function()
        local game = FakeGame.install({ server = true })
        ModData.getOrCreate("IndoorClimateLite").version = 1
        assert.are.equal(1, game.modData.IndoorClimateLite.version)
        sendServerCommand("p1", "IndoorClimateLite", "sample", { airC = 18 })
        assert.are.same({ player = "p1", module = "IndoorClimateLite", command = "sample", args = { airC = 18 } },
            game.sent[1])
    end)
end)
