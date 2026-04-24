local function GetItemData(name)
    local ok, data = pcall(function()
        return exports['corex-inventory']:GetItemData(name)
    end)
    if ok and data then return data end
    local lo, up = string.lower(name), string.upper(name)
    return (Items   and (Items[lo]   or Items[up]))
        or (Weapons and (Weapons[lo] or Weapons[up]))
        or (Ammo    and (Ammo[lo]    or Ammo[up]))
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
            local data = GetItemData(pick.name)
            if data then
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
    RollTier = RollTier,
    GenerateLoot = GenerateLoot,
    RegisterContainer = RegisterContainer,
    UnregisterContainer = UnregisterContainer,
}
