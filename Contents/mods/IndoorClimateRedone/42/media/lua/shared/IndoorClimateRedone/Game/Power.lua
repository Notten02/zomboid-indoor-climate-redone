-- Electricity: the grid, and generators.
--
-- Game adapter. Rooms are heated by the grid alone (`Power.grid`), as in the original: a generator powers devices
-- (heaters, fans) but does not make a building reach the powered target. A square's generator power comes from
-- `haveElectricity()`, which reports generator power only (the game's range and fuel rules); `hasGridPower()` is the
-- grid at that square.

local Power = {}

-- True while the world's grid power is on.
function Power.grid()
    local world = getWorld()
    return world ~= nil and world:isHydroPowerOn() == true
end

-- What powers `square`: "grid", "generator", or nil for none. The grid wins when both do.
function Power.at(square)
    if not square then
        return nil
    end
    if square:hasGridPower() == true then
        return "grid"
    end
    if square:haveElectricity() == true then
        return "generator"
    end
    return nil
end

return Power
