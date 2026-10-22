-- The mod's own heat sources (IsoHeatSource) in the game's cell, by owner.
--
-- The game's air temperature for a square counts every heat source near it, ours included. The room simulation
-- reads that air as the "vanilla" air a room drifts toward, so it must read it without ours, or a room would warm
-- itself through its own bridge source. `HeatSources.without` takes ours out of the cell for one reading. In single
-- player the simulation and the client's sources share one cell; on a dedicated server there are none of ours.
--
-- Game adapter.
--
--   HeatSources.place(owner, square, radius, temperature)   adds or moves the owner's source
--   HeatSources.remove(owner)
--   HeatSources.get(owner)                                   { source, cell, x, y, z, radius, temperature } or nil
--   HeatSources.without(fn, ...)                             fn(...) with none of ours in the cell
--   HeatSources.clear()

local HeatSources = {}

-- owner -> record
local records = {}

-- Adds the owner's heat source on `square`, or updates the one it has. The game takes whole degrees.
function HeatSources.place(owner, square, radius, temperature)
    local cell = getCell()
    if not cell or not square or not IsoHeatSource then
        HeatSources.remove(owner)
        return nil
    end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local record = records[owner]
    if record and record.cell == cell and record.x == x and record.y == y and record.z == z then
        record.source:setRadius(radius)
        record.source:setTemperature(temperature)
    else
        HeatSources.remove(owner)
        record = { source = IsoHeatSource.new(x, y, z, radius, temperature), cell = cell, x = x, y = y, z = z }
        cell:addHeatSource(record.source)
        records[owner] = record
    end
    record.radius = radius
    record.temperature = temperature
    return record
end

function HeatSources.remove(owner)
    local record = records[owner]
    if not record then
        return
    end
    record.cell:removeHeatSource(record.source)
    records[owner] = nil
end

function HeatSources.get(owner)
    return records[owner]
end

-- Calls fn(...) with every one of our sources out of the cell, puts them back and returns what fn returned.
function HeatSources.without(fn, ...)
    local removed = {}
    for _, record in pairs(records) do
        record.cell:removeHeatSource(record.source)
        removed[#removed + 1] = record
    end
    local ok, a, b = pcall(fn, ...)
    for _, record in ipairs(removed) do
        record.cell:addHeatSource(record.source)
    end
    if not ok then
        error(a)
    end
    return a, b
end

-- Removes all of ours.
function HeatSources.clear()
    for owner in pairs(records) do
        HeatSources.remove(owner)
    end
    records = {}
end

return HeatSources
