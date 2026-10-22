-- The devices' context menus, as in the original:
--   - in the inventory, "Install ..." on a device puts it down with the game's own place-item tool (a favourite item
--     cannot be placed);
--   - on a placed device, "Turn On ..." or "Turn Off ..." (greyed out with the reason when it has no electricity, or
--     for the propane heater no fuel), and for the propane heater the tank's fill and "Insert", "Replace" or
--     "Remove Propane Tank". Inserting uses a non-empty tank from the player's inventory; the old tank comes back with
--     what was left in it.
-- The choices go to the server (Devices.request), which checks them and owns the state.
--
--   DeviceMenu.inventory(playerNum, context, items)
--   DeviceMenu.world(playerNum, context, worldObjects)

local Heater = require("IndoorClimateRedone/Heater")
local Propane = require("IndoorClimateRedone/Propane")
local Devices = require("IndoorClimateRedone/Game/Devices")

local DeviceMenu = {}

-- The translation of `key`, or `fallback` while no translation has it.
local function text(key, fallback)
    local value = getText(key)
    if value and value ~= key then
        return value
    end
    return fallback
end

local function disable(option, reason)
    option.notAvailable = true
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip.description = reason
    option.toolTip = tooltip
end

local function place(item, player)
    local modData = item:getModData()
    modData.ICLHeaterActive = nil
    ISInventoryPaneContextMenu.onPlaceItemOnGround({ item }, player)
end

function DeviceMenu.inventory(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player or not context or not items then
        return
    end
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        local profile = Heater.profile(item:getFullType())
        if profile and not item:getWorldItem() then
            local option = context:addOption(text(profile.installKey, profile.installText), item, place, player)
            if item:isFavorite() then
                disable(option, text("Tooltip_CantPlaceFavoriteItems", "Favorite items cannot be placed."))
            end
            return
        end
    end
end

local function where(object)
    local square = object:getSquare()
    return { x = square:getX(), y = square:getY(), z = square:getZ(), fullType = object:getItem():getFullType() }
end

local function switch(object, player, on)
    local args = where(object)
    args.active = on
    Devices.request(player, Devices.SWITCH, args)
end

local function tank(object, player, action, item)
    local args = where(object)
    args.action = action
    args.tankId = item and item:getID() or nil
    Devices.request(player, Devices.TANK, args)
end

local function propaneOptions(context, object, player)
    local present, fuel = Propane.state(Devices.modData(object))
    local info
    if present then
        info = string.format(text("ContextMenu_ICLPropaneRemaining", "Propane: %d%%"), Propane.percent(fuel))
    else
        info = text("ContextMenu_ICLNoPropaneTank", "Propane tank: not installed")
    end
    context:addOption(info, nil, nil).notAvailable = true
    local full = Devices.findFullTank(player:getInventory())
    if full then
        local label = present and text("ContextMenu_ICLReplacePropaneTank", "Replace Propane Tank")
            or text("ContextMenu_ICLInsertPropaneTank", "Insert Propane Tank")
        context:addOption(label, object, tank, player, "insert", full)
    end
    if present then
        context:addOption(text("ContextMenu_ICLRemovePropaneTank", "Remove Propane Tank"), object, tank, player,
            "remove", nil)
    end
end

local function deviceIn(worldObjects)
    local square = nil
    for _, candidate in ipairs(worldObjects) do
        if Devices.isDevice(candidate) then
            return candidate
        end
        square = square or candidate:getSquare()
    end
    return Devices.on(square)
end

function DeviceMenu.world(playerNum, context, worldObjects)
    local player = getSpecificPlayer(playerNum)
    if not player or not context or not worldObjects then
        return
    end
    local object = deviceIn(worldObjects)
    local profile = object and Devices.profileOf(object) or nil
    if not profile then
        return
    end
    local propane = Heater.usesPropane(profile)
    if propane then
        propaneOptions(context, object, player)
    end
    if Devices.isOn(object) then
        context:addOption(text(profile.turnOffKey, profile.turnOffText), object, switch, player, false)
        return
    end
    local option = context:addOption(text(profile.turnOnKey, profile.turnOnText), object, switch, player, true)
    if not Devices.canRun(object) then
        if propane then
            disable(option, text("ContextMenu_ICLPropaneHeaterNeedsFuel", "Requires a non-empty propane tank"))
        else
            disable(option, text("ContextMenu_ICLHeaterNeedsElectricity", "Requires electricity"))
        end
    end
end

return DeviceMenu
