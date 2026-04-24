local function GetItemData(itemName)
    return CXE_Loot.GetItemData(itemName)
end

local function RollLootTier()
    return CXE_Loot.RollTier(Config.SupplyDrop.lootTable)
end

local function GenerateLoot()
    local count = math.random(Config.SupplyDrop.itemsPerCrate.min,
                              Config.SupplyDrop.itemsPerCrate.max)
    local loot = {}
    for _ = 1, count do
        local tier = RollLootTier()
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
        loot[1] = { name = 'bandage', count = 1, label = 'Bandage',
                    image = 'bandage.png', rarity = 'common', taken = false }
    end
    return loot
end

local handler = {}

function handler.start(state)
    local zones = Config.SupplyDrop.dropZones
    local zone  = zones[math.random(1, #zones)]
    state.location     = zone.coords
    state.locationName = zone.label

    state.ctx = {
        items      = GenerateLoot(),
        dropped    = false,
        registered = false,
    }

    CXE_Debug('Info', ('Supply drop scheduled · %s · drop in %ds · %d items'):format(
        zone.label, state.announceLead, #state.ctx.items))
end

function handler.tick(state)
    if not state.ctx.dropped and os.time() >= state.dropAt then
        state.ctx.dropped = true

        local evId = state.id
        local ok = CXE_Loot.RegisterContainer(
            evId,
            state.ctx.items,
            state.label or 'Supply Crate',
            function(containerId, source)
                CXE_Debug('Info', ('Supply drop depleted by src=%d'):format(source or 0))
                CXE_Loot.UnregisterContainer(evId)
                CXE_UnregisterSharedRewardCrate(evId)
                CXE_EndEvent(evId, 'depleted')
            end,
            {
                consumeOnClose = true,
                coords = state.location,
            }
        )
        state.ctx.registered = ok

        CXE_RegisterSharedRewardCrate(evId, {
            model = Config.SupplyDrop.crateModel,
            coords = state.location,
            center = state.location,
            heading = Config.SupplyDrop.crateHeading or 0.0,
            flare = false,
            marker = true,
            createBlipImmediately = false,
            syncRadius = 1200.0,
            target = {
                text = 'Search Supply Crate',
                icon = 'fa-box-open',
                distance = 2.2,
                event = 'corex-events:client:supplyDrop_searchCrate',
                data = { eventId = evId },
            },
        })

        CXE_BroadcastUpdate(state, { dropped = true })
        CXE_Debug('Info', 'Supply drop landed: ' .. state.id .. ' · registered=' .. tostring(ok))
    end
end

function handler.stop(state, reason)
    if state.ctx and state.ctx.registered then
        CXE_Loot.UnregisterContainer(state.id)
    end
    CXE_UnregisterSharedRewardCrate(state.id)
    CXE_Debug('Info', ('Supply drop stop · %s · reason=%s'):format(state.id, reason or '?'))
end

CreateThread(function()
    while not CXE_RegisterHandler do Wait(100) end
    CXE_RegisterHandler('supply_drop', handler)
    CXE_Debug('Info', 'supply_drop server handler registered')
end)
