-- How a player's room sample travels from the server to their client.
--
-- The server sends each player only their own sample: when it first has one, when something the client shows or
-- uses changed (another room, power, open doors or windows, the number of devices in reach, or a temperature that
-- moved by CHANGE_C or more since the last send), and at least every HEARTBEAT_MS real milliseconds while it lasts. When the player leaves the
-- simulated rooms the server sends CLEAR once. A client that (re)joins sends HELLO, and the server sends it its
-- sample at once.
--
-- Pure: the time is passed in. The server keeps one record per player and passes it back in.
--
--   local command, record = Sync.next(record, sample, nowMs)   -- command: Sync.SAMPLE, Sync.CLEAR or nil

local Sync = {}

Sync.MODULE = "IndoorClimateRedone"
Sync.SAMPLE = "sample"
Sync.CLEAR = "clear"
Sync.HELLO = "hello"

Sync.CHANGE_C = 0.2
Sync.HEARTBEAT_MS = 30000

-- Temperatures that are sent again once they moved by CHANGE_C.
Sync.TEMPERATURES = { "airC", "baseRoomC", "targetC", "vanillaAirC", "outdoorC" }
-- Fields that are sent again on any change. leakScore counts as changed when it moved by 0.01.
Sync.EXACT = { "roomKey", "buildingKey", "roomKind", "indoors", "powered", "openDoors", "openWindows",
    "envelopeComplete", "heaterCount" }
Sync.LEAK_STEP = 0.01

local function moved(a, b, step)
    if type(a) ~= "number" or type(b) ~= "number" then
        return a ~= b
    end
    return math.abs(a - b) >= step
end

-- True when `sample` differs enough from `sent` (the sample last sent) to be sent again.
function Sync.changed(sent, sample)
    if not sent then
        return true
    end
    for _, name in ipairs(Sync.EXACT) do
        if sent[name] ~= sample[name] then
            return true
        end
    end
    for _, name in ipairs(Sync.TEMPERATURES) do
        if moved(sent[name], sample[name], Sync.CHANGE_C) then
            return true
        end
    end
    return moved(sent.leakScore, sample.leakScore, Sync.LEAK_STEP)
end

-- What to send for a player whose current sample is `sample` (nil when they are not in a simulated room), given
-- their record (nil for a player nothing was sent to yet). Returns the command (or nil) and the new record:
--   { sample = <the table last looked at>, sent = <the sample last sent, or false after CLEAR>, atMs }
function Sync.next(record, sample, nowMs)
    if not sample then
        if record and record.sent then
            return Sync.CLEAR, { sample = nil, sent = false, atMs = nowMs }
        end
        return nil, record or { sample = nil, sent = false, atMs = nowMs }
    end
    if record and record.sent and nowMs - record.atMs < Sync.HEARTBEAT_MS
        and (record.sample == sample or not Sync.changed(record.sent, sample)) then
        record.sample = sample
        return nil, record
    end
    return Sync.SAMPLE, { sample = sample, sent = sample, atMs = nowMs }
end

local function plain(value)
    local kind = type(value)
    return kind == "number" or kind == "string" or kind == "boolean"
end

-- The command arguments for a sample: its plain fields, and the online ID of the player it belongs to (so a client
-- with more than one local player can tell them apart).
function Sync.pack(sample, playerId)
    local args = {}
    for name, value in pairs(sample) do
        if plain(value) then
            args[name] = value
        end
    end
    args.playerId = playerId
    return args
end

-- The sample in received command arguments (the plain fields without playerId), or nil when they are not a sample.
function Sync.unpack(args)
    if type(args) ~= "table" or type(args.airC) ~= "number" then
        return nil
    end
    local sample = {}
    for name, value in pairs(args) do
        if name ~= "playerId" and plain(value) then
            sample[name] = value
        end
    end
    return sample
end

return Sync
