local handler = {}

function handler.start(state)
    local zones = Config.Extraction.zones
    local zone  = zones[math.random(1, #zones)]
    state.location     = zone.coords
    state.locationName = zone.label

    local cfg = Config.Extraction
    state.ctx = {
        zombieCount = math.random(cfg.zombieCount.min, cfg.zombieCount.max),
        spawned     = false,
        hostSource  = nil,
        waitStamp   = 0,
        rewardSpawned = false,
    }

    CXE_Debug('Info', ('Extraction · %s · %d zombies · hold %ds · drop in %ds'):format(
        zone.label, state.ctx.zombieCount, cfg.holdTime, state.announceLead or 60))
end

function handler.tick(state)
    if state.ctx.spawned then return end
    if os.time() < state.dropAt then return end

    local host
    for _, srcStr in ipairs(GetPlayers()) do
        local src = tonumber(srcStr)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local d = #(GetEntityCoords(ped) - state.location)
            if d < 600.0 then host = src break end
        end
    end

    if not host then
        if (os.time() - state.ctx.waitStamp) > 10 then
            CXE_Debug('Verbose', ('Extraction %s · waiting'):format(state.id))
            state.ctx.waitStamp = os.time()
        end
        return
    end

    state.ctx.hostSource = host
    state.ctx.spawned    = true

    TriggerClientEvent('corex-events:client:extractionSpawn', host, state.id, {
        location = { x = state.location.x, y = state.location.y, z = state.location.z },
        count    = state.ctx.zombieCount,
        spread   = Config.Extraction.zombieSpread,
    })

    CXE_BroadcastUpdate(state, { spawned = true })
    CXE_Debug('Info', ('Extraction %s · host=%d · go!'):format(state.id, host))
end

function handler.stop(state, reason)
    CXE_Loot.UnregisterContainer(state.id .. ':reward')
    CXE_UnregisterSharedRewardCrate(state.id .. ':reward')
    if reason ~= 'expired' and reason ~= 'depleted' then return end
    if state.ctx and state.ctx.rewardSpawned then return end
    if state.ctx then state.ctx.rewardSpawned = true end
    if not state.location then return end

    local rewardId = state.id .. ':reward'
    local cfg = Config.Extraction
    local items = CXE_Loot.GenerateLoot(cfg.lootTable, cfg.itemsPerReward)
    local rewardCoords = vector3(state.location.x, state.location.y, state.location.z)

    CXE_Loot.RegisterContainer(rewardId, items, 'Extraction Reward', function(containerId)
        CXE_Loot.UnregisterContainer(rewardId)
        CXE_UnregisterSharedRewardCrate(rewardId)
        exports['corex-core']:BroadcastNearby(
            rewardCoords,
            1000.0,
            'corex-events:client:extractionRewardExpired',
            rewardId
        )
    end, {
        consumeOnClose = true,
        coords = rewardCoords,
    })

    CXE_RegisterSharedRewardCrate(rewardId, {
        model = 'prop_mil_crate_02',
        coords = rewardCoords,
        center = rewardCoords,
        heading = 0.0,
        revealRadius = Config.Extraction.radius,
        blipLabel = 'Extraction Crate',
        blipColor = 5,
        syncRadius = 1000.0,
        target = {
            text = '[E] Open Extraction Crate',
            icon = 'fa-box-open',
            distance = 3.0,
            event = 'corex-events:client:extraction_openCrate',
            data = { crateId = rewardId },
        },
    })

    exports['corex-core']:BroadcastNearby(
        rewardCoords,
        1000.0,
        'corex-events:client:extractionReward',
        rewardId,
        { location = { x = state.location.x, y = state.location.y, z = state.location.z } }
    )

    CXE_Debug('Info', 'Extraction reward: ' .. rewardId)
end

CreateThread(function()
    while not CXE_RegisterHandler do Wait(100) end
    CXE_RegisterHandler('extraction', handler)
end)
