-- Smoke test, client side: reports whether the mod is active here.
require "PZE2E/PZE2E"

PZE2E.answer("icrModActive", function()
    local player = getPlayer()
    return {
        active = getActivatedMods():contains("IndoorClimateRedone"),
        username = player and player:getUsername() or nil,
    }
end)
