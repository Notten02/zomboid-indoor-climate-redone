-- Smoke test: the mod is active on the dedicated server and on a joined client.
if not isServer() then return end
require "PZE2E/PZE2E"

PZE2E.test("mod is active on the server and the client", {
    function(ctx)
        PZE2E.check(getActivatedMods():contains("IndoorClimateRedone"), "server has IndoorClimateRedone active")
        PZE2E.ask(ctx.player, "icrModActive", {}, "client")
    end,
    function(ctx)
        if not ctx.answers.client then return "wait" end
        PZE2E.check(ctx.answers.client.active == true, "client %s has IndoorClimateRedone active",
            tostring(ctx.answers.client.username))
    end,
}, { startAfter = 2, every = 1 })
