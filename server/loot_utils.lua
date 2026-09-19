-- Item definitions come from whichever inventory CoreX has. There is no bundled
-- catalog behind this any more: carrying a copy of one inventory's item file
-- meant this resource could not start at all once that inventory was deleted
-- from disk, and the copy went stale the moment either side changed.
local function GetItemData(name)
    return CoreXInventoryBridge.GetItemDefinition(name)
end

--- Everything event loot needs about an item, whether or not the installed
--- inventory has ever heard of it. An item nobody can describe still drops.
local function DescribeItem(name)
    local definition = GetItemData(name)
    if type(definition) == 'table' then return definition end
    return { label = name, image = 'default.png', rarity = 'common' }
end

local function RollTier(lootTable)
    local roll = math.random()
    local cum = 0
    for _, tier in ipairs(lootTable) do
        cum = cum + tier.chance
        if roll <= cum then return tier.items end
    end
    return lootTable[1].items
end

local function GenerateLoot(lootTable, countRange)
    local count = math.random(countRange.min, countRange.max)
    local loot = {}
    for _ = 1, count do
        local tier = RollTier(lootTable)
        if tier and #tier > 0 then
            local pick = tier[math.random(1, #tier)]
            local data = DescribeItem(pick.name)
            loot[#loot + 1] = {
                name   = pick.name,
                count  = math.random(pick.min, pick.max),
                label  = data.label  or pick.name,
                image  = data.image  or 'default.png',
                rarity = data.rarity or 'common',
                taken  = false,
            }
        end
    end
    if #loot == 0 then
        loot[1] = { name = 'rifle_ammo', count = 20, label = 'Rifle Ammo', image = 'default.png', rarity = 'common', taken = false }
    end
    return loot
end

local function RegisterContainer(eventId, items, label, onDepleted, options)
    options = options or {}
    local ok, err = pcall(function()
        return exports['corex-loot']:RegisterDynamicContainer(eventId, items, {
            label      = label,
            onDepleted = onDepleted,
            consumeOnClose = options.consumeOnClose == true,
            coords = options.coords or options.location or options.center,
            interactDistance = options.interactDistance,
        })
    end)
    if not ok then
        CXE_Debug('Error', 'RegisterDynamicContainer failed: ' .. tostring(err))
        return false
    end
    return true
end

local function UnregisterContainer(eventId)
    pcall(function() exports['corex-loot']:UnregisterDynamicContainer(eventId) end)
end

CXE_Loot = {
    GetItemData = GetItemData,
    DescribeItem = DescribeItem,
    RollTier = RollTier,
    GenerateLoot = GenerateLoot,
    RegisterContainer = RegisterContainer,
    UnregisterContainer = UnregisterContainer,
}
