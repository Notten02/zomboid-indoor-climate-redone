-- The room samples the server sent to this client's players (multiplayer only; see Sync).
--
-- A sample is kept until the server replaces or clears it. While the player sits in a vehicle or stands outside
-- the rooms, the sample is not handed out even before the server's CLEAR arrives, so the client never shows a room
-- the player has just left.
--
--   Samples.receive(command, args)   an OnServerCommand of Sync.MODULE
--   Samples.of(player)               the player's sample, or nil
--   Samples.roomAt(square, player)   the room temperature and leak score at a square in the player's own room
--   Samples.hello(player)            asks the server for the player's sample
--   Samples.clear()

local Sync = require("IndoorClimateRedone/Sync")
local Places = require("IndoorClimateRedone/Game/Places")

local Samples = {}

-- online ID -> sample
local received = {}
-- player -> { square, descriptor } of the square the player was last seen on
local seen = {}

function Samples.receive(command, args)
    if type(args) ~= "table" or args.playerId == nil then
        return false
    end
    if command == Sync.SAMPLE then
        local sample = Sync.unpack(args)
        if not sample then
            return false
        end
        received[args.playerId] = sample
        return true
    elseif command == Sync.CLEAR then
        received[args.playerId] = nil
        return true
    end
    return false
end

-- The descriptor of the player's square, worked out again only when the player moved to another square.
local function whereIs(player)
    local square = player:getCurrentSquare()
    local last = seen[player]
    if not last or last.square ~= square then
        last = { square = square, descriptor = Places.describe(square) }
        seen[player] = last
    end
    return last.descriptor
end

function Samples.of(player)
    local sample = received[player:getOnlineID()]
    if not sample or player:getVehicle() or not whereIs(player) then
        return nil
    end
    return sample
end

-- The client knows only its players' own rooms: a square in the room the player is in gets that room's
-- temperature, any other square nil.
function Samples.roomAt(square, player)
    if not player then
        return nil
    end
    local sample = Samples.of(player)
    if not sample then
        return nil
    end
    local here = whereIs(player)
    local there = Places.describe(square)
    if not here or not there or there.key ~= here.key or Places.roomKey(there) ~= Places.roomKey(here) then
        return nil
    end
    return tonumber(sample.baseRoomC) or tonumber(sample.airC), tonumber(sample.leakScore) or 0
end

function Samples.hello(player)
    sendClientCommand(player, Sync.MODULE, Sync.HELLO, {})
end

function Samples.clear()
    received = {}
    seen = {}
end

return Samples
