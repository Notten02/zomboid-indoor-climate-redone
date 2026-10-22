-- Body warmth, client side: the outdoor air, the game's air for the character, the air the thermoregulator works with
-- and the core temperature, as this client sees them.
require "PZE2E/PZE2E"

PZE2E.answer("icrWarmth", function()
    local player = getPlayer()
    local climate = getClimateManager()
    local thermo = player:getBodyDamage():getThermoregulator()
    local live = IndoorClimateLite.getLiveTemperatureSample(player)
    return {
        outdoorC = climate:getTemperature(),
        characterAirC = climate:getAirTemperatureForCharacter(player, false),
        thermoAirC = thermo:getTemperatureAir(),
        coreC = thermo:getCoreTemperature(),
        roomAirC = live and live.airC or nil,
    }
end)
