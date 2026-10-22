-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- Room air temperature maths, with the original mod's numbers as the expected behaviour.
local Config = require("IndoorClimateRedone/Config")
local Model = require("IndoorClimateRedone/Model")

local EPS = 1e-9

describe("Model.advance", function()
    it("closes the gap by 1 - e^(-rate * hours)", function()
        assert.near(10 + 10 * (1 - math.exp(-1)), Model.advance(10, 20, 1, 1), EPS)
        assert.near(20 - 20 * (1 - math.exp(-0.06 * 5)), Model.advance(20, 0, 5, 0.06), EPS)
    end)

    it("gives the same result for one long step as for several short ones", function()
        local once = Model.advance(5, 22, 3, 0.7)
        local thrice = Model.advance(Model.advance(Model.advance(5, 22, 1, 0.7), 22, 1, 0.7), 22, 1, 0.7)
        assert.near(once, thrice, EPS)
    end)

    it("does not move without time, without a rate or at the target", function()
        assert.are.equal(10, Model.advance(10, 20, 0, 1))
        assert.are.equal(10, Model.advance(10, 20, -2, 1))
        assert.are.equal(10, Model.advance(10, 20, 1, 0))
        assert.are.equal(10, Model.advance(10, 20, 1, -1))
        assert.are.equal(20, Model.advance(20, 20, 1, 1))
    end)

    it("never overshoots the target", function()
        assert.near(20, Model.advance(10, 20, 1000, 10), EPS)
        assert.is_true(Model.advance(10, 20, 1000, 10) <= 20)
    end)

    it("falls back on the target or 0 for a missing temperature", function()
        assert.are.equal(20, Model.advance(nil, 20, 1, 1))
        assert.are.equal(10, Model.advance(10, nil, 1, 1))
        assert.are.equal(0, Model.advance(nil, nil, 1, 1))
    end)
end)

describe("Model.exchange", function()
    it("moves both rooms toward their area-weighted mean and keeps the total heat", function()
        local a, b = Model.exchange(30, 10, 30, 10, 1, 3)
        assert.is_true(a < 30 and b > 10)
        assert.near(30 * 30 + 10 * 10, a * 30 + b * 10, 1e-6)
    end)

    it("ends at the area-weighted mean", function()
        local a, b = Model.exchange(30, 10, 30, 10, 1000, 3)
        assert.near(25, a, EPS)
        assert.near(25, b, EPS)
    end)

    it("blends by 1 - e^(-rate * hours)", function()
        local a, b = Model.exchange(20, 10, 1, 1, 2, 0.1)
        local blend = 1 - math.exp(-0.2)
        assert.near(20 - 5 * blend, a, EPS)
        assert.near(10 + 5 * blend, b, EPS)
    end)

    it("counts an area below 1 as 1", function()
        local a, b = Model.exchange(20, 10, 0, nil, 1000, 1)
        assert.near(15, a, EPS)
        assert.near(15, b, EPS)
    end)

    it("leaves equal rooms, no time or no rate alone", function()
        assert.are.same({ 15, 15 }, { Model.exchange(15, 15, 4, 9, 1, 3) })
        assert.are.same({ 20, 10 }, { Model.exchange(20, 10, 4, 9, 0, 3) })
        assert.are.same({ 20, 10 }, { Model.exchange(20, 10, 4, 9, 1, 0) })
    end)
end)

describe("Model rates and targets", function()
    local config = Config.defaults()

    it("loses 0.06 per hour sealed and 12 times that wide open", function()
        assert.near(0.06, Model.unpoweredRate(config, 0), EPS)
        assert.near(0.72, Model.unpoweredRate(config, 1), EPS)
        assert.near(0.06 * (1 + 11 * 0.5), Model.unpoweredRate(config, 0.5), EPS)
    end)

    it("caps the leak score at 0..1", function()
        assert.near(0.72, Model.unpoweredRate(config, 3), EPS)
        assert.near(0.06, Model.unpoweredRate(config, -1), EPS)
        assert.near(0.06, Model.unpoweredRate(config, nil), EPS)
    end)

    it("heads a sealed powered room for 22 C", function()
        assert.near(22, Model.poweredTarget(config, -10, 0), EPS)
    end)

    it("pulls a leaking powered room toward outdoor air by leak times 0.75", function()
        assert.near(22 + (-10 - 22) * 0.75, Model.poweredTarget(config, -10, 1), EPS)
        assert.near(22 + (-10 - 22) * 0.375, Model.poweredTarget(config, -10, 0.5), EPS)
    end)

    it("follows the sandbox values", function()
        local c = Config.read({ PoweredTargetC = 25, PoweredLeakInfluence = 0, SealedLossPerHour = 0.1,
            BreachMultiplier = 2 })
        assert.near(25, Model.poweredTarget(c, -10, 1), EPS)
        assert.near(0.2, Model.unpoweredRate(c, 1), EPS)
    end)

    it("targets outdoor air without power", function()
        assert.are.equal(-3, Model.target(config, false, -3, 1))
        assert.near(Model.poweredTarget(config, -3, 0.4), Model.target(config, true, -3, 0.4), EPS)
    end)
end)

describe("Model.step", function()
    local config = Config.defaults()

    it("warms a powered room toward 22 C at 3 per hour", function()
        assert.near(Model.advance(5, 22, 1, 3), Model.step(config, 5, 1, true, 0, 5, 0), EPS)
    end)

    it("lets a sealed unpowered room keep its heat for days", function()
        local after = Model.step(config, 22, 24, false, 0, 0, 0)
        assert.near(22 * math.exp(-0.06 * 24), after, EPS)
        assert.is_true(after > 5)
    end)

    it("cools an open unpowered room 12 times faster", function()
        assert.near(22 * math.exp(-0.72), Model.step(config, 22, 1, false, 0, 0, 1), EPS)
    end)

    it("warms an unpowered room toward warmer vanilla air at no less than 2 per hour", function()
        assert.near(Model.advance(5, 18, 1, 2), Model.step(config, 5, 1, false, 0, 18, 0), EPS)
    end)

    it("ignores vanilla air that is not warmer than the room", function()
        assert.near(Model.advance(20, 0, 1, 0.06), Model.step(config, 20, 1, false, 0, 10, 0), EPS)
    end)

    it("uses the outdoor air as target when it is warmer than vanilla air", function()
        assert.near(Model.advance(5, 30, 1, 2), Model.step(config, 5, 1, false, 30, 18, 0), EPS)
    end)

    it("ignores vanilla air with power on", function()
        assert.near(Model.advance(5, 22, 1, 3), Model.step(config, 5, 1, true, 0, 40, 0), EPS)
    end)

    it("starts a room without a temperature at vanilla air, then outdoor air, then 15 C", function()
        assert.are.equal(12, Model.step(config, nil, 0, false, 3, 12, 0))
        assert.are.equal(3, Model.step(config, nil, 0, false, 3, nil, 0))
        assert.are.equal(15, Model.step(config, nil, 0, false, nil, nil, 0))
    end)

    it("keeps the room between -80 and 80 C", function()
        assert.are.equal(80, Model.step(config, 200, 0, false, 0, 0, 0))
        assert.are.equal(-80, Model.step(config, -200, 0, false, 0, 0, 0))
    end)
end)

describe("Model.initial", function()
    it("starts an unvisited building 2 C above outdoor air", function()
        assert.are.equal(7, Model.initial(Config.defaults(), 5))
        assert.are.equal(5, Model.initial(Config.read({ UnvisitedOffsetC = 0 }), 5))
    end)

    it("assumes 15 C outdoors when outdoor air is unknown", function()
        assert.are.equal(17, Model.initial(Config.defaults(), nil))
    end)

    it("stays between -80 and 80 C", function()
        assert.are.equal(80, Model.initial(Config.defaults(), 79))
    end)
end)

describe("Model.elapsed", function()
    local config = Config.defaults()

    it("counts the hours since the last update", function()
        assert.are.same({ 1.5, 10 }, { Model.elapsed(config, 10, 11.5) })
    end)

    it("is 0 when the clock went back", function()
        assert.are.equal(0, (Model.elapsed(config, 20, 10)))
    end)

    it("is 0 for a state that was never updated", function()
        assert.are.same({ 0, 10 }, { Model.elapsed(config, nil, 10) })
    end)

    it("catches up on at most 168 hours and moves the start of the window", function()
        assert.are.same({ 168, 832 }, { Model.elapsed(config, 0, 1000) })
    end)
end)
