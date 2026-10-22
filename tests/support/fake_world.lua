-- A stand-in for the parts of the game map the mod reads: squares, map buildings and rooms, player-built regions,
-- walls, doors, windows, window frames and barricades, players and the cell's heat sources. Like FakeGame it is not
-- a simulation: only the calls the mod makes exist.
--
--   local world = FakeWorld.install(game)          -- after FakeGame.install; sets getCell, instanceof, players ...
--   local house = world:building({ x = 10, y = 10, w = 6, h = 4, rooms = {
--       { id = 1, x1 = 10, y1 = 10, x2 = 12, y2 = 13 },        -- z defaults to 0
--       { id = 2, x1 = 13, y1 = 10, x2 = 15, y2 = 13 } } })
--   world:door(13, 11, 0, "W")                       -- on the west edge of (13,11), between rooms 1 and 2
--   world:window(10, 10, 0, "N", { open = true })    -- in the outer wall
--   world:passage(13, 12, 0, "W")                    -- no wall on that edge
--   local player = world:player(11, 11, 0)
--   local heater = world:device(11, 12, 0, "IndoorClimateLite.ElectricHeater", { on = true })
--   local generator = world:generator(5, 5, 0, { fuel = 10 })   -- running; powers squares within 20 tiles
--   player:getInventory():AddItem(world:item("Base.PropaneTank", { fuel = 0.5 }))
--
-- Walls: an edge between two squares of different rooms, or between a room and anything else, is a wall unless
-- world:passage opened it. Doors and windows sit on the north ("N") or west ("W") edge of their square; the square
-- across that edge is their opposite square.

local FakeWorld = {}

local function list(items)
    return {
        size = function() return #items end,
        get = function(_, index) return items[index + 1] end,
        items = items,
    }
end

local function coord(x, y, z)
    return x .. "," .. y .. "," .. z
end

local World = {}
World.__index = World

function World:square(x, y, z)
    return self.squares[coord(x, y, z or 0)]
end

local function edgeKey(a, b)
    local ka, kb = coord(a.x, a.y, a.z), coord(b.x, b.y, b.z)
    if ka < kb then
        return ka .. "|" .. kb
    end
    return kb .. "|" .. ka
end

local function newSquare(world, x, y, z)
    local sq = { x = x, y = y, z = z, objects = {}, special = {}, worldObjects = {}, world = world }
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:getN() return world:square(self.x, self.y - 1, self.z) end
    function sq:getS() return world:square(self.x, self.y + 1, self.z) end
    function sq:getW() return world:square(self.x - 1, self.y, self.z) end
    function sq:getE() return world:square(self.x + 1, self.y, self.z) end
    function sq:isInARoom() return self.roomDef ~= nil end
    function sq:getRoomDef() return self.roomDef end
    function sq:getRoom() return nil end
    function sq:getBuilding() return self.buildingObject end
    function sq:getRoomIDString() return self.roomDef and tostring(self.roomDef.id) or "-1" end
    function sq:getIsoWorldRegion() return self.region end
    function sq:getObjects() return list(self.objects) end
    function sq:getSpecialObjects() return list(self.special) end
    function sq:getWorldObjects() return list(self.worldObjects) end
    function sq:getGenerator() return self.generatorObject end
    function sq:getIsoDoor() return nil end
    -- 42.21 has getWindow() and getWindow(<edge>), no boolean form.
    function sq:getWindow(edge)
        assert(edge == nil, "getWindow takes an edge, not a boolean, in 42.21")
        return nil
    end
    function sq:getChunk() return nil end
    function sq:hasGridPower() return world.game.power == true end
    function sq:haveElectricity() return self.generator == true or world:generatorPowers(self) end
    function sq:isBlockedTo(other)
        if world.passages[edgeKey(self, other)] then
            return false
        end
        local a = self.roomDef or self.region
        local b = other.roomDef or other.region
        return a ~= b
    end
    world.squares[coord(x, y, z)] = sq
    world.allSquares[coord(x, y, z)] = sq
    return sq
end

function World:ensureSquare(x, y, z)
    return self:square(x, y, z) or newSquare(self, x, y, z)
end

-- Ground squares (z 0) over a rectangle: the loaded map.
function World:ground(x1, y1, x2, y2)
    for x = x1, x2 do
        for y = y1, y2 do
            self:ensureSquare(x, y, 0)
        end
    end
end

-- A map building. `spec`: x, y, w, h (the BuildingDef bounds), rooms = { { id, x1, y1, x2, y2, z } }. Ground around
-- the bounds (2 squares) is created as well. Returns the building object.
function World:building(spec)
    local def = { x = spec.x, y = spec.y, w = spec.w, h = spec.h, rooms = {} }
    local building = { def = def, id = spec.id or (#self.buildings + 1) }
    function def:getX() return self.x end
    function def:getY() return self.y end
    function def:getW() return self.w end
    function def:getH() return self.h end
    function def:getIDString() return tostring(building.id) end
    function def:getRooms() return list(self.rooms) end
    function building:getDef() return self.def end
    function building:getID() return self.id end
    self:ground(spec.x - 2, spec.y - 2, spec.x + spec.w + 1, spec.y + spec.h + 1)
    for _, r in ipairs(spec.rooms or {}) do
        local z = r.z or 0
        local roomDef = { id = r.id, z = z, area = (r.x2 - r.x1 + 1) * (r.y2 - r.y1 + 1) }
        function roomDef:getIDString() return tostring(self.id) end
        function roomDef:getID() return self.id end
        function roomDef:getZ() return self.z end
        function roomDef:getArea() return self.area end
        def.rooms[#def.rooms + 1] = roomDef
        for x = r.x1, r.x2 do
            for y = r.y1, r.y2 do
                local sq = self:ensureSquare(x, y, z)
                sq.roomDef = roomDef
                sq.buildingObject = not spec.detached and building or nil
            end
        end
    end
    self.buildings[#self.buildings + 1] = building
    return building
end

-- A player-built region over the given squares { {x, y}, ... } on floor z. opts: roofed (default true), id.
function World:region(squares, z, opts)
    opts = opts or {}
    local region = { id = opts.id or (100 + #self.regions), roofed = opts.roofed ~= false, size = #squares }
    function region:getID() return self.id end
    function region:isPlayerRoom() return true end
    function region:isFullyRoofed() return self.roofed end
    function region:getSquareSize() return self.size end
    for _, p in ipairs(squares) do
        self:ensureSquare(p[1], p[2], 0)
        self:ensureSquare(p[1], p[2], z).region = region
    end
    self.regions[#self.regions + 1] = region
    return region
end

local function opposite(world, x, y, z, side)
    if side == "N" then
        return world:square(x, y - 1, z)
    end
    return world:square(x - 1, y, z)
end

local function newObject(world, class, x, y, z, side, fields)
    local object = fields or {}
    object.__class = class
    object.pos = { x = x, y = y, z = z, side = side }
    function object:getSquare()
        return world:square(self.pos.x, self.pos.y, self.pos.z)
    end
    function object:getOppositeSquare()
        return opposite(world, self.pos.x, self.pos.y, self.pos.z, self.pos.side)
    end
    local sq = world:ensureSquare(x, y, z)
    sq.objects[#sq.objects + 1] = object
    sq.special[#sq.special + 1] = object
    return object
end

local function barricade(spec)
    if not spec then
        return nil
    end
    return {
        isMetalBar = function() return spec.metalBar == true end,
        isMetal = function() return spec.metal == true end,
        getNumPlanks = function() return spec.planks or 0 end,
    }
end

local function addBarricades(object)
    function object:getBarricadeOnSameSquare() return barricade(self.barricades and self.barricades[1]) end
    function object:getBarricadeOnOppositeSquare() return barricade(self.barricades and self.barricades[2]) end
end

function World:door(x, y, z, side, opts)
    local door = newObject(self, "IsoDoor", x, y, z, side, { open = opts and opts.open == true })
    function door:IsOpen() return self.open end
    addBarricades(door)
    return door
end

-- opts: open, smashed, glassRemoved, barricades = { same, opposite } ({ planks = n, metal, metalBar })
function World:window(x, y, z, side, opts)
    opts = opts or {}
    local window = newObject(self, "IsoWindow", x, y, z, side, { open = opts.open == true,
        smashed = opts.smashed == true, glassRemoved = opts.glassRemoved == true, barricades = opts.barricades })
    function window:IsOpen() return self.open end
    function window:isSmashed() return self.smashed end
    function window:isGlassRemoved() return self.glassRemoved end
    addBarricades(window)
    return window
end

-- opts: hasWindow, barricades
function World:frame(x, y, z, side, opts)
    opts = opts or {}
    local frame = newObject(self, "IsoWindowFrame", x, y, z, side, { withWindow = opts.hasWindow == true,
        barricades = opts.barricades })
    function frame:hasWindow() return self.withWindow end
    addBarricades(frame)
    return frame
end

-- A player-built door or window (IsoThumpable). kind: "door" or "window".
function World:thumpable(x, y, z, side, kind, opts)
    opts = opts or {}
    local object = newObject(self, "IsoThumpable", x, y, z, side, { open = opts.open == true })
    function object:isDoor() return kind == "door" end
    function object:isWindow() return kind == "window" end
    function object:IsOpen() return self.open end
    function object:getProperties() return { has = function() return false end } end
    addBarricades(object)
    return object
end

-- Takes an object off its square (it then has no square).
function World:remove(object)
    local sq = object:getSquare()
    for _, field in ipairs({ "objects", "special" }) do
        for index, o in ipairs(sq[field]) do
            if o == object then
                table.remove(sq[field], index)
                break
            end
        end
    end
    object.pos = { x = -9999, y = -9999, z = 0, side = "N" }
end

-- An edge without a wall (an open archway).
function World:passage(x, y, z, side)
    local a = self:square(x, y, z)
    local b = opposite(self, x, y, z, side)
    self.passages[edgeKey(a, b)] = true
end

-- Unloads (or loads again) the map over a rectangle, all floors.
function World:unload(x1, y1, x2, y2)
    for key, sq in pairs(self.squares) do
        if sq.x >= x1 and sq.x <= x2 and sq.y >= y1 and sq.y <= y2 then
            self.squares[key] = nil
        end
    end
end

function World:reload()
    for key, sq in pairs(self.allSquares) do
        self.squares[key] = sq
    end
end

-- An inventory item. opts: fuel (a drainable's fill, 0 to 1), name.
function World:item(fullType, opts)
    opts = opts or {}
    self.nextItemId = (self.nextItemId or 0) + 1
    local item = { fullType = fullType, modData = {}, id = self.nextItemId, fuel = opts.fuel or 1,
        name = opts.name or fullType:match("%.(.+)$") }
    function item:getFullType() return self.fullType end
    function item:getModData() return self.modData end
    function item:getID() return self.id end
    function item:getDisplayName() return self.name end
    function item:getWorldItem() return self.worldItem end
    function item:getContainer() return self.container end
    function item:isFavorite() return self.favorite == true end
    function item:getCurrentUsesFloat() return self.fuel end
    function item:setUsedDelta(value) self.fuel = value end
    return item
end

-- An item container (a player's inventory).
function World:container()
    local world = self
    local container = { items = {} }
    function container:getItems() return list(self.items) end
    function container:AddItem(item)
        if type(item) == "string" then
            item = world:item(item)
        end
        item.container = self
        self.items[#self.items + 1] = item
        return item
    end
    function container:Remove(item)
        for index, other in ipairs(self.items) do
            if other == item then
                table.remove(self.items, index)
                item.container = nil
                return
            end
        end
    end
    function container:getType() return self.type or "none" end
    function container:getSourceGrid() return self.square end
    container.__class = "ItemContainer"
    return container
end

-- A device (or any item) placed on the ground: an IsoWorldInventoryObject. opts: on, fuelHour, tank (propane fill,
-- 0 to 1), at ("x:y:z" where it was switched on).
function World:device(x, y, z, fullType, opts)
    opts = opts or {}
    local world = self
    local item = self:item(fullType)
    if opts.on then
        item.modData.ICLHeaterActive = true
        item.modData.ICLHeaterFuelHour = opts.fuelHour
        item.modData.ICLDeviceAt = opts.at
    end
    if opts.tank then
        item.modData.ICLPropaneTankPresent = true
        item.modData.ICLPropaneFuel = opts.tank
    end
    local object = { __class = "IsoWorldInventoryObject", item = item, pos = { x = x, y = y, z = z } }
    item.worldItem = object
    function object:getItem() return self.item end
    function object:getSquare() return world:square(self.pos.x, self.pos.y, self.pos.z) end
    local sq = self:ensureSquare(x, y, z)
    sq.worldObjects[#sq.worldObjects + 1] = object
    return object
end

-- Takes a placed item off the ground (it then has no square).
function World:pickUp(object)
    local sq = object:getSquare()
    for index, o in ipairs(sq.worldObjects) do
        if o == object then
            table.remove(sq.worldObjects, index)
            break
        end
    end
    object.pos = { x = -9999, y = -9999, z = 0 }
end

-- A generator, running and connected unless opts say otherwise. opts: fuel (litres, default 10), off, unplugged.
-- It powers squares within 20 tiles and 3 floors while it runs and has fuel.
function World:generator(x, y, z, opts)
    opts = opts or {}
    local world = self
    local generator = { fuel = opts.fuel or 10, activated = not opts.off, connected = not opts.unplugged,
        synced = 0, refreshed = 0, pos = { x = x, y = y, z = z } }
    function generator:getSquare() return world:square(self.pos.x, self.pos.y, self.pos.z) end
    function generator:getObjectIndex() return self.removed and -1 or 0 end
    function generator:isActivated() return self.activated end
    function generator:setActivated(on) self.activated = on end
    function generator:isConnected() return self.connected end
    function generator:getFuel() return self.fuel end
    function generator:setFuel(fuel) self.fuel = fuel end
    function generator:sync() self.synced = self.synced + 1 end
    function generator:setSurroundingElectricity() self.refreshed = self.refreshed + 1 end
    function generator:getBasePowerConsumptionString() return "0.020 L/h" end
    function generator:getTotalPowerUsingString() return "0.030 L/h" end
    self:ensureSquare(x, y, z).generatorObject = generator
    self.generators[#self.generators + 1] = generator
    return generator
end

function World:generatorPowers(sq)
    for _, generator in ipairs(self.generators) do
        local at = generator.pos
        local dx, dy = at.x - sq.x, at.y - sq.y
        if generator.activated and generator.connected and generator.fuel > 0 and math.abs(at.z - sq.z) <= 3
            and dx * dx + dy * dy <= 400 then
            return true
        end
    end
    return false
end

-- A player standing on (x, y, z). Move them with player:moveTo(x, y, z).
function World:player(x, y, z, name)
    local world = self
    local player = { pos = { x = x, y = y, z = z or 0 }, modData = {}, index = #self.players,
        onlineId = 100 + #self.players, name = name or ("player" .. (#self.players + 1)) }
    function player:getCurrentSquare() return world:square(self.pos.x, self.pos.y, self.pos.z) end
    function player:getVehicle() return self.vehicle end
    function player:isDead() return self.dead == true end
    function player:getModData() return self.modData end
    function player:getUsername() return self.name end
    function player:getOnlineID() return self.onlineId end
    function player:getPlayerNum() return self.index end
    function player:isLocalPlayer() return self.remote ~= true end
    function player:moveTo(px, py, pz) self.pos = { x = px, y = py, z = pz or 0 } end
    function player:getPrimaryHandItem() return self.primaryHand end
    function player:getSecondaryHandItem() return self.secondaryHand end
    function player:setPrimaryHandItem(item) self.primaryHand = item end
    function player:setSecondaryHandItem(item) self.secondaryHand = item end
    function player:removeFromHands(item)
        if self.primaryHand == item then self.primaryHand = nil end
        if self.secondaryHand == item then self.secondaryHand = nil end
    end
    function player:getX() return self.pos.x + 0.5 end
    function player:getY() return self.pos.y + 0.5 end
    player.inventory = self:container()
    function player:getInventory() return self.inventory end
    self.players[#self.players + 1] = player
    return player
end

---@param game table the FakeGame
function FakeWorld.install(game)
    local world = setmetatable({ game = game, squares = {}, allSquares = {}, buildings = {}, regions = {},
        passages = {}, players = {}, generators = {} }, World)
    game.power = true
    -- One cell, as in the game: its heat sources are game.heatSources.
    local cell = {}
    function cell:getGridSquare(x, y, z) return world:square(x, y, z) end
    function cell:addHeatSource(source)
        game.heatSources[#game.heatSources + 1] = source
    end
    function cell:removeHeatSource(source)
        for index, s in ipairs(game.heatSources) do
            if s == source then
                table.remove(game.heatSources, index)
                return
            end
        end
    end
    _G.getCell = function() return cell end
    _G.IsoHeatSource = {
        new = function(x, y, z, radius, temperature)
            local source = { x = x, y = y, z = z, radius = radius, temperature = temperature }
            function source:getX() return self.x end
            function source:getY() return self.y end
            function source:getZ() return self.z end
            function source:getRadius() return self.radius end
            function source:getTemperature() return self.temperature end
            function source:setRadius(r) self.radius = r end
            function source:setTemperature(t) self.temperature = t end
            return source
        end,
    }
    _G.getWorld = function()
        return { isHydroPowerOn = function() return game.power == true end }
    end
    _G.instanceof = function(object, class)
        return type(object) == "table" and object.__class == class
    end
    _G.IsoFlagType = {}
    _G.getOnlinePlayers = function() return list(world.players) end
    _G.getNumActivePlayers = function() return #world.players end
    _G.getSpecificPlayer = function(index) return world.players[index + 1] end
    _G.instanceItem = function(fullType) return world:item(fullType) end
    -- Item moves the server reports to clients: game.itemsSent = { { "add" or "remove", container, item } }
    game.itemsSent = {}
    _G.sendAddItemToContainer = function(container, item)
        game.itemsSent[#game.itemsSent + 1] = { "add", container, item }
    end
    _G.sendRemoveItemFromContainer = function(container, item)
        game.itemsSent[#game.itemsSent + 1] = { "remove", container, item }
    end
    return world
end

return FakeWorld
