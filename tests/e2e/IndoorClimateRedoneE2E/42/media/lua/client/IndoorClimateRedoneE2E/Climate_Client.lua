-- Room simulation tests, client side: opens doors and windows the way a player does (walk there, then the vanilla
-- timed action), reports what this client sees of them, and moves the player with the admin teleport command.
require "PZE2E/PZE2E"

local function openingAt(args)
    local sq = getCell():getGridSquare(args.x, args.y, args.z)
    if not sq then return nil, sq end
    local objects = sq:getSpecialObjects()
    for i = 0, objects:size() - 1 do
        local o = objects:get(i)
        if instanceof(o, "IsoDoor") or instanceof(o, "IsoWindow") then return o, sq end
    end
    return nil, sq
end

PZE2E.answer("icrToggle", function(args)
    local player = getPlayer()
    local object, sq = openingAt(args)
    if not object then return { queued = false, reason = "nothing there" } end
    if not luautils.walkAdjWindowOrDoor(player, sq, object) then return { queued = false, reason = "no path" } end
    if instanceof(object, "IsoDoor") then
        ISTimedActionQueue.add(ISOpenCloseDoor:new(player, object))
    else
        ISTimedActionQueue.add(ISOpenCloseWindow:new(player, object))
    end
    return { queued = true }
end)

PZE2E.answer("icrOpening", function(args)
    local object = openingAt(args)
    return { found = object ~= nil, open = object ~= nil and object:IsOpen() }
end)

PZE2E.answer("icrTeleport", function(args)
    SendCommandToServer(string.format("/teleportto %d,%d,%d", args.x, args.y, args.z))
    return { sent = true }
end)
