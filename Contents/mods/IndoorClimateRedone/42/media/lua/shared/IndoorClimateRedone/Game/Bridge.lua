-- The native bridge: a small heat source on the player's square that makes the game's own air there match the
-- simulated room when the room is warmer than the game thinks. Vanilla code that reads the air at the player (the
-- temperature display, body warmth) then sees the room. The original mod's rules:
--   - only with the NativeBridge option on, the simulation active, a room sample, and not in a vehicle;
--   - only when the room is more than 0.25 C warmer than the game's own air (a cooler room is not bridged);
--   - radius 1, at the room temperature minus the game's indoor correction for a source at distance zero,
--     clamp(vanilla air - 30, -7, 7), rounded to whole degrees;
--   - it moves with the player from square to square.
-- The original placed it on the player's client only. In multiplayer the server works out a player's body warmth
-- from the server's own air, so the source is placed there too: on each client for its local players, and on a
-- dedicated server for every online player.
--
-- Game adapter.
--
--   Bridge.update(player, sample, settings)   places, moves or removes the player's source
--   Bridge.follow(player, sample, settings)   the same, only when the sample, square or vehicle changed
--   Bridge.prune(players)                     removes the sources of players not in the list
--   Bridge.remove(player) / Bridge.clear()

local Config = require("IndoorClimateRedone/Config")
local HeatSources = require("IndoorClimateRedone/Game/HeatSources")

local Bridge = {}

-- player -> { sample, square, inVehicle } the source was last placed for
local applied = {}

Bridge.RADIUS = 1
Bridge.MARGIN_C = 0.25

-- The source temperature that makes the game's air at distance zero come out at roomC.
function Bridge.sourceTemperature(roomC, vanillaAirC)
    local correction = Config.clamp(vanillaAirC - 30.0, -7.0, 7.0)
    return math.floor(roomC - correction + 0.5)
end

function Bridge.remove(player)
    HeatSources.remove(player)
    applied[player] = nil
end

function Bridge.update(player, sample, settings)
    local square = player:getCurrentSquare()
    local roomC = sample and (tonumber(sample.baseRoomC) or tonumber(sample.airC)) or nil
    local vanillaAirC = sample and tonumber(sample.vanillaAirC) or nil
    if not settings.NativeBridge or not square or player:getVehicle() or not roomC or not vanillaAirC
        or roomC <= vanillaAirC + Bridge.MARGIN_C then
        Bridge.remove(player)
        return nil
    end
    return HeatSources.place(player, square, Bridge.RADIUS, Bridge.sourceTemperature(roomC, vanillaAirC))
end

function Bridge.follow(player, sample, settings)
    local square = player:getCurrentSquare()
    local inVehicle = player:getVehicle() ~= nil
    local last = applied[player]
    if last and last.sample == sample and last.square == square and last.inVehicle == inVehicle then
        return
    end
    Bridge.update(player, sample, settings)
    applied[player] = { sample = sample, square = square, inVehicle = inVehicle }
end

function Bridge.prune(players)
    local keep = {}
    for _, player in ipairs(players) do
        keep[player] = true
    end
    for player in pairs(applied) do
        if not keep[player] then
            Bridge.remove(player)
        end
    end
end

function Bridge.clear()
    for player in pairs(applied) do
        HeatSources.remove(player)
    end
    applied = {}
end

return Bridge
