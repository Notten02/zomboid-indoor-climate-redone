-- The two-room test house (see envelope_spec) in a fake game, with the mod's files loaded the way the game loads
-- them for the side asked for.
--
--   local game, world, o, Climate = House.setup()                    -- a dedicated server
--   House.setup({ side = "sp" })                                     -- single player: server and client files
--   House.setup({ side = "client" })                                 -- a multiplayer client
--   opts: power (grid on), sandbox = { option = value }
-- Off the server, every tick also fires OnPlayerUpdate for each player, as the game does for local players.
-- o holds the openings: inner (door between the rooms), front (door), west and east (windows).
-- Climate is nil on a multiplayer client, where the server files stop at their first line.
local FakeGame = require("support/fake_game")
local FakeWorld = require("support/fake_world")

local House = {}

House.KEY = "building:x10:y10:w6:h4"

-- Forgets the mod's loaded modules, so the next require wires them to the current fake game.
function House.fresh()
    for name in pairs(package.loaded) do
        if name:match("^IndoorClimateRedone/") then
            package.loaded[name] = nil
        end
    end
end

function House.setup(opts)
    opts = opts or {}
    local side = opts.side or "server"
    local game = FakeGame.install({ server = side == "server", client = side == "client" })
    local world = FakeWorld.install(game)
    world:building({ x = 10, y = 10, w = 6, h = 4, rooms = {
        { id = 1, x1 = 10, y1 = 10, x2 = 12, y2 = 13 },
        { id = 2, x1 = 13, y1 = 10, x2 = 15, y2 = 13 },
    } })
    local o = {
        inner = world:door(13, 11, 0, "W"),
        front = world:door(10, 12, 0, "W"),
        west = world:window(11, 10, 0, "N"),
        east = world:window(14, 10, 0, "N"),
    }
    game.power = opts.power == true
    game.climate.outdoorC = 10
    for name, value in pairs(opts.sandbox or {}) do
        game.sandbox[name] = value
    end
    House.fresh()
    require("IndoorClimateRedone/Game/Api")
    if side ~= "server" then
        require("IndoorClimateRedone/Client")
    end
    require("IndoorClimateRedone/Main")
    game.events.OnInitGlobalModData.trigger(false)
    if side ~= "server" then
        game.events.OnTick.Add(function()
            House.playerUpdate(game, world)
        end)
    end
    local Climate = nil
    if side ~= "client" then
        Climate = require("IndoorClimateRedone/Climate")
    end
    return game, world, o, Climate
end

-- Fires OnPlayerUpdate for every local player, as the game does each tick.
function House.playerUpdate(game, world)
    for _, player in ipairs(world.players) do
        game.events.OnPlayerUpdate.trigger(player)
    end
end

return House
