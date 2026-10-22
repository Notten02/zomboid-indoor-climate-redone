-- Sends each online player their own room sample (see Sync for when). Dedicated server only: in single player the
-- client reads the simulation directly.
--
--   Sender.flush(players, sampleOf, nowMs)   sends what is due; players nobody passes any more are forgotten
--   Sender.greet(player, sample, nowMs)      a client (re)joined: sends its sample, or CLEAR, at once
--   Sender.reset()

local Sync = require("IndoorClimateRedone/Sync")

local Sender = {}

-- player -> Sync record
local records = {}

-- Messages sent since the last reset (for tests and diagnostics).
Sender.sent = 0

local function send(player, command, sample)
    local playerId = player:getOnlineID()
    if command == Sync.SAMPLE then
        sendServerCommand(player, Sync.MODULE, Sync.SAMPLE, Sync.pack(sample, playerId))
    else
        sendServerCommand(player, Sync.MODULE, Sync.CLEAR, { playerId = playerId })
    end
    Sender.sent = Sender.sent + 1
end

-- Sends every player in `players` what is due for them; `sampleOf(player)` is their current sample or nil.
function Sender.flush(players, sampleOf, nowMs)
    local online = {}
    for _, player in ipairs(players) do
        online[player] = true
        local command, record = Sync.next(records[player], sampleOf(player), nowMs)
        records[player] = record
        if command then
            send(player, command, record.sent or nil)
        end
    end
    for player in pairs(records) do
        if not online[player] then
            records[player] = nil
        end
    end
end

function Sender.greet(player, sample, nowMs)
    if sample then
        records[player] = { sample = sample, sent = sample, atMs = nowMs }
        send(player, Sync.SAMPLE, sample)
    else
        records[player] = { sample = nil, sent = false, atMs = nowMs }
        send(player, Sync.CLEAR, nil)
    end
end

function Sender.reset()
    records = {}
    Sender.sent = 0
end

return Sender
