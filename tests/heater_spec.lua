-- LuaLS's bundled luassert definitions omit the optional failure-message argument.
---@diagnostic disable: redundant-parameter
-- The devices' figures and how they change the air (Heater), and the propane heater's tank (Propane). The original
-- mod's numbers are the behaviour spec.
local Config = require("IndoorClimateRedone/Config")
local Heater = require("IndoorClimateRedone/Heater")
local Propane = require("IndoorClimateRedone/Propane")

local config = Config.defaults()

local function device(fullType, x, y, z)
    return { fullType = fullType, x = x or 0, y = y or 0, z = z or 0 }
end

describe("Heater profiles", function()
    it("keep the original item types and figures", function()
        local standard = Heater.profile("IndoorClimateLite.ElectricHeater")
        local premium = Heater.profile("IndoorClimateLite.PremiumHeater")
        local fan = Heater.profile("IndoorClimateLite.StandingFan")
        local propane = Heater.profile("IndoorClimateLite.PropaneHeater")
        assert.are.same({ 6, 40, "delta", 12 },
            { standard.radius, standard.sourceTemperature, standard.heatMode, standard.centerDeltaC })
        assert.are.same({ 12, 25, "target", 25 },
            { premium.radius, premium.sourceTemperature, premium.heatMode, premium.targetC })
        assert.are.same({ 8, false, "delta", -10, 0.20 },
            { fan.radius, fan.nativeHeatSource, fan.heatMode, fan.centerDeltaC, fan.generatorFuelPerHour })
        assert.are.same({ 10, 25, "target", 25, 0.025 },
            { propane.radius, propane.sourceTemperature, propane.heatMode, propane.targetC, propane.propaneUsePerHour })
        assert.is_true(Heater.usesPropane(propane))
        assert.is_false(Heater.usesPropane(standard))
        assert.is_nil(Heater.profile("Base.Hammer"))
        assert.is_nil(Heater.profile(nil))
        assert.are.equal(12, Heater.MAX_RADIUS)
    end)

    it("draw generator fuel at the sandbox rate, the fan at its own", function()
        assert.are.equal(0.04, Heater.generatorFuelPerHour(Heater.profile(Heater.STANDARD), config))
        assert.are.equal(0.20, Heater.generatorFuelPerHour(Heater.profile(Heater.FAN), config))
        local custom = Config.read({ HeaterGeneratorFuelPerHour = 0.1 })
        assert.are.equal(0.1, Heater.generatorFuelPerHour(Heater.profile(Heater.PREMIUM), custom))
    end)
end)

describe("Heater.delta", function()
    it("adds the cheap heater's 12 C at its square, fading to nothing at its radius", function()
        local devices = { device(Heater.STANDARD) }
        assert.near(12, Heater.delta(devices, 0, 0, 0, 10, 0, config), 1e-9)
        assert.near(6, Heater.delta(devices, 3, 0, 0, 10, 0, config), 1e-9)
        assert.near(12 * (1 - 5 / 6), Heater.delta(devices, 3, 4, 0, 10, 0, config), 1e-9)
        assert.are.equal(0, (Heater.delta(devices, 6, 0, 0, 10, 0, config)))
        assert.are.equal(0, (Heater.delta(devices, 0, 0, 1, 10, 0, config)))
    end)

    it("lifts the air toward a target heater's 25 C, taking only the strongest lift", function()
        local devices = { device(Heater.PREMIUM), device(Heater.PROPANE, 1, 0, 0) }
        -- At (0,0): premium lifts 10 by 15 * 1, propane by 15 * 0.9.
        assert.near(15, Heater.delta(devices, 0, 0, 0, 10, 0, config), 1e-9)
        assert.near(0, Heater.delta(devices, 0, 0, 0, 25, 0, config), 1e-9)
        assert.near(0, Heater.delta(devices, 0, 0, 0, 30, 0, config), 1e-9)
    end)

    it("adds delta devices up to +16 C and -20 C, on top of the lift", function()
        local hot = { device(Heater.STANDARD), device(Heater.STANDARD), device(Heater.STANDARD) }
        assert.near(16, Heater.delta(hot, 0, 0, 0, 10, 0, config), 1e-9)
        local cold = { device(Heater.FAN), device(Heater.FAN), device(Heater.FAN) }
        assert.near(-20, Heater.delta(cold, 0, 0, 0, 30, 0, config), 1e-9)
        local mixed = { device(Heater.PREMIUM), device(Heater.FAN) }
        assert.near(15 - 10, Heater.delta(mixed, 0, 0, 0, 10, 0, config), 1e-9)
    end)

    it("is weakened by leaks: a room that leaks completely keeps a quarter", function()
        local devices = { device(Heater.STANDARD) }
        local delta, count, radius, retention = Heater.delta(devices, 0, 0, 0, 10, 1, config)
        assert.near(3, delta, 1e-9)
        assert.are.same({ 1, 6, 0.25 }, { count, radius, retention })
        assert.near(0.625, Heater.retention(0.5, config), 1e-9)
        assert.are.equal(1, Heater.retention(0.5, Config.read({ PoweredLeakInfluence = 0 })))
    end)

    it("counts the devices in reach and their largest radius", function()
        local devices = { device(Heater.STANDARD), device(Heater.PREMIUM, 7, 0, 0), device(Heater.FAN, 50, 0, 0) }
        local _, count, radius = Heater.delta(devices, 1, 0, 0, 10, 0, config)
        assert.are.same({ 2, 12 }, { count, radius })
        local _, none, noRadius, retention = Heater.delta({}, 0, 0, 0, 10, 0, config)
        assert.are.same({ 0, 0, 1 }, { none, noRadius, retention })
    end)
end)

describe("Heater.adjust", function()
    it("returns the changed air, held to -80..45 C", function()
        local air, delta, count = Heater.adjust({ device(Heater.STANDARD) }, 0, 0, 0, 20, 0, config)
        assert.are.same({ 32, 12, 1 }, { air, delta, count })
        assert.are.equal(45, (Heater.adjust({ device(Heater.STANDARD) }, 0, 0, 0, 40, 0, config)))
        assert.are.equal(-80, (Heater.adjust({ device(Heater.FAN) }, 0, 0, 0, -75, 0, config)))
        assert.are.equal(15, (Heater.adjust({}, 0, 0, 0, nil, 0, config)))
    end)
end)

describe("Propane", function()
    it("keeps the tank in the original's mod data fields", function()
        local modData = {}
        assert.are.same({ false, 0 }, { Propane.state(modData) })
        Propane.set(modData, true, 0.6)
        assert.are.same({ ICLPropaneTankPresent = true, ICLPropaneFuel = 0.6 }, modData)
        assert.is_true(Propane.hasFuel(modData))
        Propane.set(modData, true, 3)
        assert.are.equal(1, modData.ICLPropaneFuel)
        Propane.set(modData, false)
        assert.are.same({}, modData)
        assert.is_false(Propane.hasFuel(modData))
        assert.is_false(Propane.hasFuel(nil))
    end)

    it("burns 0.025 of a tank an hour", function()
        local profile = Heater.profile(Heater.PROPANE)
        local modData = { ICLPropaneTankPresent = true, ICLPropaneFuel = 0.5 }
        local hasFuel, remaining, changed = Propane.burn(modData, profile, 4)
        assert.is_true(hasFuel)
        assert.near(0.4, remaining, 1e-9)
        assert.is_true(changed)
        assert.near(0.4, modData.ICLPropaneFuel, 1e-9)
        hasFuel, remaining = Propane.burn(modData, profile, 100)
        assert.are.same({ false, 0 }, { hasFuel, remaining })
        assert.are.same({ false, 0, false }, { Propane.burn({}, profile, 1) })
        assert.are.same({ true, 0.5, false },
            { Propane.burn({ ICLPropaneTankPresent = true, ICLPropaneFuel = 0.5 }, profile, 0) })
    end)

    it("shows whole percent", function()
        assert.are.equal(40, Propane.percent(0.404))
        assert.are.equal(41, Propane.percent(0.405))
        assert.are.equal(0, Propane.percent(nil))
    end)
end)
