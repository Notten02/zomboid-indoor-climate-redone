-- Room air temperature: how one room's air moves toward its target, and how two connected rooms share heat.
--
-- Every change is exponential easing: over `hours` at `rate` per hour, the gap to the target closes by
-- 1 - e^(-rate * hours). While the inputs stay the same, stepping 1 hour twice gives the same result as stepping
-- 2 hours once.
--
-- A powered room heads for the powered target (22 C by default), pulled toward outdoor air by its leaks. An
-- unpowered room drifts toward outdoor air, slowly when sealed (0.06 per hour) and up to 12 times faster when its
-- doors and windows are open or broken. Vanilla air warmer than the room (sun, fire, a heat source) warms an
-- unpowered room at no less than 2 per hour.
--
-- Pure: settings come from Config.read and are passed in, as are all temperatures and times (in world hours).

local Config = require("IndoorClimateRedone/Config")

local clamp = Config.clamp

local Model = {}

-- Room air never leaves this range.
Model.MIN_C = -80.0
Model.MAX_C = 80.0

-- `current` eased toward `target` over `hours` at `rate` per hour.
function Model.advance(current, target, hours, rate)
    current = tonumber(current) or tonumber(target) or 0
    target = tonumber(target) or current
    hours = math.max(0, tonumber(hours) or 0)
    rate = math.max(0, tonumber(rate) or 0)
    if hours <= 0 or rate <= 0 or current == target then
        return current
    end
    return current + (target - current) * (1.0 - math.exp(-rate * hours))
end

-- Two rooms of the given floor areas eased toward their area-weighted mean over `hours` at `rate` per hour.
-- Returns the two new temperatures. The total heat (temperature times area) stays the same.
function Model.exchange(tempA, tempB, areaA, areaB, hours, rate)
    tempA = tonumber(tempA) or 0
    tempB = tonumber(tempB) or tempA
    areaA = math.max(1, tonumber(areaA) or 1)
    areaB = math.max(1, tonumber(areaB) or 1)
    hours = math.max(0, tonumber(hours) or 0)
    rate = math.max(0, tonumber(rate) or 0)
    if hours <= 0 or rate <= 0 or tempA == tempB then
        return tempA, tempB
    end
    local mean = (tempA * areaA + tempB * areaB) / (areaA + areaB)
    local blend = 1.0 - math.exp(-rate * hours)
    return tempA + (mean - tempA) * blend, tempB + (mean - tempB) * blend
end

-- Heat-loss rate per hour of an unpowered room with the given leak score (0 sealed .. 1 wide open): the sealed loss
-- rate, multiplied by up to BreachMultiplier.
function Model.unpoweredRate(config, leakScore)
    local leak = clamp(leakScore or 0, 0, 1)
    return config.SealedLossPerHour * (1.0 + (config.BreachMultiplier - 1.0) * leak)
end

-- The temperature a powered room heads for: the powered target, moved toward outdoor air by leak score times
-- PoweredLeakInfluence.
function Model.poweredTarget(config, outdoorC, leakScore)
    local target = tonumber(config.PoweredTargetC) or 22.0
    local outdoor = tonumber(outdoorC) or target
    local leak = clamp(leakScore or 0, 0, 1)
    local influence = clamp(config.PoweredLeakInfluence or 0, 0, 1)
    return target + (outdoor - target) * leak * influence
end

-- The temperature a room heads for right now: the powered target with power, else outdoor air.
function Model.target(config, powered, outdoorC, leakScore)
    if powered then
        return Model.poweredTarget(config, outdoorC, leakScore)
    end
    return outdoorC
end

-- One room's temperature after `hours` with the given power, outdoor air, vanilla air at the room and leak score.
function Model.step(config, current, hours, powered, outdoorC, vanillaAirC, leakScore)
    current = tonumber(current) or tonumber(vanillaAirC) or tonumber(outdoorC) or 15
    local outdoor = tonumber(outdoorC) or current
    local vanillaAir = tonumber(vanillaAirC) or outdoor
    local target, rate
    if powered then
        target = Model.poweredTarget(config, outdoor, leakScore)
        rate = config.PoweredRatePerHour
    else
        target = outdoor
        rate = Model.unpoweredRate(config, leakScore)
        if vanillaAir > current then
            target = math.max(target, vanillaAir)
            rate = math.max(rate, config.LocalHeatRatePerHour)
        end
    end
    return clamp(Model.advance(current, target, hours, rate), Model.MIN_C, Model.MAX_C)
end

-- The starting temperature of a building nobody has visited: outdoor air plus UnvisitedOffsetC.
function Model.initial(config, outdoorC)
    local outdoor = tonumber(outdoorC) or 15.0
    local offset = tonumber(config.UnvisitedOffsetC) or 2.0
    return clamp(outdoor + offset, Model.MIN_C, Model.MAX_C)
end

-- Hours to catch up on from `lastHour` to `nowHours`: never negative (a clock that went back) and at most
-- MaxElapsedHours. The second value is the start of the window that is stepped (`nowHours` minus the first value).
function Model.elapsed(config, lastHour, nowHours)
    lastHour = tonumber(lastHour) or nowHours
    local hours = nowHours - lastHour
    if hours < 0 then
        hours = 0
    end
    if hours > config.MaxElapsedHours then
        hours = config.MaxElapsedHours
        lastHour = nowHours - hours
    end
    return hours, lastHour
end

return Model
