-- Sync tests, client side: what this client's public API says about its player's room, and the game's own air at
-- the player (raised by the bridge heat source when the room is warmer).
require "PZE2E/PZE2E"

PZE2E.answer("icrClientSample", function()
    local player = getPlayer()
    local s = IndoorClimateLite.getTemperatureSample(player)
    local climate = getClimateManager()
    return {
        source = s.source,
        active = s.active,
        indoors = s.indoors,
        roomKey = s.roomKey,
        airC = s.airC,
        baseRoomC = s.baseRoomC,
        vanillaAirC = s.vanillaAirC,
        clientAirC = climate:getAirTemperatureForSquare(player:getCurrentSquare()),
        characterAirC = climate:getAirTemperatureForCharacter(player, false),
    }
end)
