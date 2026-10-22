-- Where the devices are found, with the original mod's weights:
--   - in the game's container lists (appliance and electronics stores, Gigamart, garages, camping and propane
--     crates, closet shelves), added to ProceduralDistributions when this file loads;
--   - in warehouses and storage units: each container the game fills there rolls once more, after the game's own
--     loot, and may get one device. The chance per container is the sum of the room's weights in percent (15% in a
--     warehouse, 17% in a storage unit) times the "other loot" sandbox multiplier (at most 5). Bodies, zombie
--     inventories and kitchen appliances are skipped, and nothing already in the container is replaced.
--
--   Loot.addAll(lists)                                ProceduralDistributions.list, or a stand-in
--   Loot.fillRoomContainer(roomName, containerType, container)   the OnFillContainer handler

require("Items/ProceduralDistributions")

local Heater = require("IndoorClimateRedone/Heater")

local Loot = {}

local STANDARD, PREMIUM, FAN, PROPANE = Heater.STANDARD, Heater.PREMIUM, Heater.FAN, Heater.PROPANE

-- { item, list, weight }
Loot.LISTS = {
    -- The cheap heater: appliance shops are the best source.
    { STANDARD, "ElectronicStoreAppliances", 18 },
    { STANDARD, "GigamartHouseElectronics", 5 },
    { STANDARD, "GigamartHousewares", 2 },
    { STANDARD, "GarageTools", 2 },
    { STANDARD, "GarageMechanics", 1.5 },
    { STANDARD, "ClosetShelfGeneric", 0.4 },
    -- The premium heater is rarer.
    { PREMIUM, "ElectronicStoreAppliances", 7 },
    { PREMIUM, "GigamartHouseElectronics", 1.5 },
    { PREMIUM, "GigamartHousewares", 0.5 },
    { PREMIUM, "GarageTools", 0.35 },
    { PREMIUM, "GarageMechanics", 0.35 },
    { PREMIUM, "ClosetShelfGeneric", 0.08 },
    -- Fans follow the cheap heater.
    { FAN, "ElectronicStoreAppliances", 18 },
    { FAN, "GigamartHouseElectronics", 5 },
    { FAN, "GigamartHousewares", 2 },
    { FAN, "GarageTools", 2 },
    { FAN, "GarageMechanics", 1.5 },
    { FAN, "ClosetShelfGeneric", 0.5 },
    -- Propane heaters lean toward workshops and camping suppliers.
    { PROPANE, "ElectronicStoreAppliances", 4 },
    { PROPANE, "GigamartHouseElectronics", 1 },
    { PROPANE, "CrateCamping", 2 },
    { PROPANE, "CratePropane", 4 },
    { PROPANE, "CampingStoreGear", 2 },
    { PROPANE, "CampingStoreTools", 1 },
    { PROPANE, "GarageTools", 2 },
    { PROPANE, "GarageMechanics", 2 },
    { PROPANE, "ClosetShelfGeneric", 0.05 },
}

-- room name -> { { item, weight } }
Loot.ROOMS = {
    warehouse = { { STANDARD, 5 }, { PREMIUM, 2 }, { FAN, 5 }, { PROPANE, 3 } },
    storageunit = { { STANDARD, 6 }, { PREMIUM, 2 }, { FAN, 6 }, { PROPANE, 3 } },
}

Loot.SKIPPED_CONTAINERS = {
    corpse = true, inventoryfemale = true, inventorymale = true, zombieinventory = true,
    fridge = true, freezer = true, microwave = true, oven = true, stove = true,
}

Loot.MAX_MULTIPLIER = 5

-- Sets an item's weight in a list (adds it when it is not there). A missing list is left alone.
local function add(lists, itemType, listName, weight)
    local items = lists[listName] and lists[listName].items or nil
    if not items then
        return false
    end
    for index = 1, #items, 2 do
        if items[index] == itemType then
            items[index + 1] = weight
            return true
        end
    end
    items[#items + 1] = itemType
    items[#items + 1] = weight
    return true
end

function Loot.addAll(lists)
    for _, entry in ipairs(Loot.LISTS) do
        add(lists, entry[1], entry[2], entry[3])
    end
end

-- The sandbox "other loot" multiplier for the devices, 0 to MAX_MULTIPLIER.
function Loot.multiplier()
    local ok, modifier = pcall(ItemPickerJava.getLootModifier, STANDARD)
    local value = ok and tonumber(modifier) or nil
    if value == nil then
        value = tonumber(SandboxVars and SandboxVars.OtherLootNew) or 1
    end
    return math.max(0, math.min(Loot.MAX_MULTIPLIER, value))
end

-- One item from the weighted entries (ZombRand), and the entries' total weight.
function Loot.pick(entries)
    local total = 0
    for _, entry in ipairs(entries) do
        total = total + entry[2]
    end
    local roll = ZombRand(math.max(1, math.floor(total * 1000))) / 1000
    for _, entry in ipairs(entries) do
        roll = roll - entry[2]
        if roll < 0 then
            return entry[1], total
        end
    end
    return entries[#entries][1], total
end

local function containerType(given, container)
    local name = string.lower(tostring(given or ""))
    if name == "" then
        name = string.lower(tostring(container:getType() or ""))
    end
    return name
end

function Loot.fillRoomContainer(roomName, givenType, container)
    local entries = Loot.ROOMS[string.lower(tostring(roomName or ""))]
    -- Some refills pass a container description rather than a container in the world.
    if not entries or not container or not instanceof(container, "ItemContainer") or not container:getSourceGrid() then
        return false
    end
    if Loot.SKIPPED_CONTAINERS[containerType(givenType, container)] then
        return false
    end
    local itemType, total = Loot.pick(entries)
    local chance = math.max(0, math.min(100, total * Loot.multiplier()))
    if ZombRand(10000) >= math.floor(chance * 100) then
        return false
    end
    container:AddItem(itemType)
    return true
end

Loot.addAll(ProceduralDistributions.list)
Events.OnFillContainer.Add(Loot.fillRoomContainer)

return Loot
