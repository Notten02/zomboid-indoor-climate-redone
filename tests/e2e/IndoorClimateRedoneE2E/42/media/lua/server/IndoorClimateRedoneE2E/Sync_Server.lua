-- Sync on a dedicated server: the client's public API serves the sample the server simulated for its player, and
-- the bridge makes the game's air at the player match a room warmer than it.
if not isServer() then return end
require "PZE2E/PZE2E"

local Climate = require("IndoorClimateRedone/Climate")

PZE2E.test("the client sees the room the server simulates", {
    function(ctx)
        if not Climate.sample(ctx.player) then return "wait" end
        PZE2E.ask(ctx.player, "icrClientSample", {}, "client")
    end,
    function(ctx)
        local c = ctx.answers.client
        if not c then return "wait" end
        local s = Climate.sample(ctx.player)
        PZE2E.log("server %s", PZE2E.describe(s))
        PZE2E.log("client %s", PZE2E.describe(c))
        PZE2E.check(c.source == "IndoorClimateLite" and c.active == true, "client API is active")
        PZE2E.check(c.indoors == true and c.roomKey == s.roomKey, "client room %s, server room %s",
            tostring(c.roomKey), tostring(s.roomKey))
        -- The client's copy is at most CHANGE_C behind when sent; a house heating up moves on in the meantime.
        PZE2E.check(type(c.airC) == "number" and math.abs(c.airC - s.airC) <= 1.0,
            "client air %.2f C, server %.2f C", c.airC or -999, s.airC)
        if c.baseRoomC > c.vanillaAirC + 0.25 then
            PZE2E.check(math.abs(c.clientAirC - c.baseRoomC) <= 1.0,
                "bridge: the game's air at the player %.2f C, room %.2f C", c.clientAirC, c.baseRoomC)
        else
            PZE2E.log("room %.2f C is not warmer than the game's air %.2f C: no bridge to check", c.baseRoomC,
                c.vanillaAirC)
        end
        PZE2E.log("air for the character: client %.2f C, server %.2f C", c.characterAirC or -999,
            getClimateManager():getAirTemperatureForCharacter(ctx.player, false))
    end,
}, { startAfter = 3, every = 1, maxWaits = 12 })
