-- Mods that model indoor temperature themselves. With one of them enabled this mod stays off, as the original did:
-- no room simulation, and the public API reports itself inactive.
--
-- Game adapter: reads the list of enabled mods. The same on a server, its clients and in single player.

local Conflicts = {}

-- Realistic Temperature, under its two mod IDs.
Conflicts.MODS = { "RC_RealisticColdMod", "RealisticTemperature" }

-- The ID of the first enabled mod in Conflicts.MODS, or nil.
function Conflicts.find()
    local mods = getActivatedMods()
    if not mods then
        return nil
    end
    for _, id in ipairs(Conflicts.MODS) do
        if mods:contains(id) or mods:contains("\\" .. id) then
            return id
        end
    end
    return nil
end

-- True when a conflicting mod is enabled.
function Conflicts.active()
    return Conflicts.find() ~= nil
end

return Conflicts
