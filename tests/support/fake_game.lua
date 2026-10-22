-- A minimal stand-in for the Project Zomboid globals the mod's adapter code uses, so the server and client wiring can
-- run offline. It is not a game simulation: only the calls the adapters make exist, and anything else fails loudly.
-- Install it inside an insulate() block; busted restores _G and package.loaded afterwards.
--
--   local game = FakeGame.install()                    -- single player: isServer() and isClient() are false
--   local game = FakeGame.install({ server = true })   -- a dedicated server
--   game.sandbox.UpdateMinutes = 5
--   game.events.OnGameStart.trigger()
--   game.advance(10)                                   -- ten game minutes of ticks
--   game.sent                                           -- { { player, module, command, args }, ... }; player is
--                                                       -- nil for a message to every client
--   game.clientSent                                     -- sendClientCommand calls, the same shape
--   game.heatSources                                    -- heat sources in the cell (FakeWorld adds them)

local FakeGame = {}

local LUA = "Contents/mods/IndoorClimateRedone/42/media/lua/"

local EVENTS = {
    "OnGameBoot", "OnGameStart", "OnServerStarted", "OnTick", "EveryOneMinute", "EveryTenMinutes", "EveryHours",
    "OnClientCommand", "OnServerCommand", "OnCreatePlayer", "OnInitGlobalModData", "OnReceiveGlobalModData",
    "OnPreDistributionMerge", "OnFillWorldObjectContextMenu", "OnFillInventoryObjectContextMenu",
    "OnPlayerUpdate", "OnDisconnect", "OnMainMenuEnter", "OnCreateUI", "LoadGridsquare", "OnObjectAdded",
    "OnObjectAboutToBeRemoved", "OnPreFillWorldObjectContextMenu", "OnPreFillInventoryObjectContextMenu",
    "OnFillContainer",
}

local function newEvent()
    local event = { handlers = {} }
    function event.Add(fn)
        event.handlers[#event.handlers + 1] = fn
    end
    function event.Remove(fn)
        for i, h in ipairs(event.handlers) do
            if h == fn then
                table.remove(event.handlers, i)
                return
            end
        end
    end
    function event.trigger(...)
        for _, h in ipairs(event.handlers) do
            h(...)
        end
    end
    return event
end

---@param opts? { server?: boolean, client?: boolean }
function FakeGame.install(opts)
    opts = opts or {}
    local game = {
        minutes = 6000, realMs = 1000000, printed = {}, sent = {}, clientSent = {}, modData = {}, mods = {},
        climate = { outdoorC = 10 }, heatSources = {},
    }

    package.path = LUA .. "server/?.lua;" .. LUA .. "client/?.lua;" .. package.path

    _G.isServer = function() return opts.server == true end
    _G.isClient = function() return opts.client == true end
    _G.getTimestampMs = function() return game.realMs end
    _G.getGameTime = function()
        return {
            getWorldAgeHours = function() return game.minutes / 60 end,
            getTimeOfDay = function() return (game.minutes / 60) % 24 end,
        }
    end
    -- Outdoor air: tests change game.climate.outdoorC. Vanilla air at a square is game.climate.vanillaC or that,
    -- raised by a heat source on that very square the way the game treats one at distance zero indoors:
    -- source temperature + clamp(air - 30, -7, 7).
    local function airAt(square)
        local air = game.climate.vanillaC or game.climate.outdoorC
        for _, source in ipairs(game.heatSources) do
            if square and source:getX() == square:getX() and source:getY() == square:getY()
                and source:getZ() == square:getZ() then
                local correction = math.max(-7, math.min(7, air - 30))
                air = math.max(air, source:getTemperature() + correction)
            end
        end
        return air
    end
    _G.getClimateManager = function()
        return {
            getTemperature = function() return game.climate.outdoorC end,
            getAirTemperatureForSquare = function(_, square) return airAt(square) end,
            getAirTemperatureForCharacter = function(_, character) return airAt(character:getCurrentSquare()) end,
        }
    end
    -- ZombRand(max) -> [0, max); ZombRand(min, max) -> [min, max). Deterministic: the middle of the range.
    _G.ZombRand = function(lo, hi)
        if hi == nil then
            lo, hi = 0, lo
        end
        return lo + math.floor((hi - lo) / 2)
    end
    -- Global ModData: game.modData[key] is the table the game would save with the world.
    _G.ModData = {
        getOrCreate = function(key)
            game.modData[key] = game.modData[key] or {}
            return game.modData[key]
        end,
        get = function(key) return game.modData[key] end,
        exists = function(key) return game.modData[key] ~= nil end,
        transmit = function() end,
    }
    -- sendServerCommand(player, module, command, args) to one client, (module, command, args) to all of them.
    _G.sendServerCommand = function(...)
        local player, module, command, args = ...
        if select("#", ...) == 3 then
            player, module, command, args = nil, player, module, command
        end
        game.sent[#game.sent + 1] = { player = player, module = module, command = command, args = args }
    end
    _G.sendClientCommand = function(player, module, command, args)
        game.clientSent[#game.clientSent + 1] = { player = player, module = module, command = command, args = args }
    end
    -- Enabled mods: game.mods["HealthRedone"] = true.
    _G.getActivatedMods = function()
        return { contains = function(_, id) return game.mods[id:gsub("^\\", "")] == true end }
    end
    _G.getText = function(key) return key end
    _G.print = function(line) game.printed[#game.printed + 1] = line end
    ---@diagnostic disable-next-line: missing-fields
    _G.SandboxVars = { IndoorClimateLite = {} }
    _G.Events = {}
    for _, name in ipairs(EVENTS) do
        _G.Events[name] = newEvent()
    end

    game.sandbox = _G.SandboxVars.IndoorClimateLite
    game.events = _G.Events

    -- Advances game time in ten ticks per game minute.
    function game.advance(minutes)
        local ticks = math.floor(minutes * 10 + 0.5)
        for _ = 1, ticks do
            local before = math.floor(game.minutes + 1e-9)
            game.minutes = game.minutes + 0.1
            game.realMs = game.realMs + 250
            game.events.OnTick.trigger()
            if math.floor(game.minutes + 1e-9) > before then
                game.events.EveryOneMinute.trigger()
                if math.floor(game.minutes + 1e-9) % 10 == 0 then
                    game.events.EveryTenMinutes.trigger()
                end
            end
        end
    end

    function game.logged(text)
        for _, line in ipairs(game.printed) do
            if line:find(text, 1, true) then
                return true
            end
        end
        return false
    end

    return game
end

return FakeGame
