local handler = {}

function handler.start(state)
    local sites = Config.AirdropCrash.crashSites
    local site  = sites[math.random(1, #sites)]
    state.location     = site.coords
    state.locationName = site.label

    local cfg = Config.AirdropCrash
    state.ctx = {
        zombieCount = math.random(cfg.zombieCount.min, cfg.zombieCount.max),
        debrisCount = math.random(cfg.debrisCount.min, cfg.debrisCount.max),
        spawned     = false,
        hostSource  = nil,
        waitStamp   = 0,
        rewardSpawned = false,
    }

    CXE_Debug('Info', ('Crash site · %s · %d zombies · %d debris · drop in %ds'):format(
        site.label, state.ctx.zombieCount, state.ctx.debrisCount, state.announceLead or 30))
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
            CXE_Debug('Verbose', ('Crash %s · waiting for player'):format(state.id))
            state.ctx.waitStamp = os.time()
        end
        return
    end

    state.ctx.hostSource = host
    state.ctx.spawned    = true

    TriggerClientEvent('corex-events:client:crashSpawn', host, state.id, {
        location = { x = state.location.x, y = state.location.y, z = state.location.z },
        count    = state.ctx.zombieCount,
        debris   = state.ctx.debrisCount,
    })

    CXE_BroadcastUpdate(state, { spawned = true })
    CXE_Debug('Info', ('Crash %s · host=%d · spawned'):format(state.id, host))
end

function handler.stop(state, reason)
    CXE_Loot.UnregisterContainer(state.id .. ':reward')
    CXE_UnregisterSharedRewardCrate(state.id .. ':reward')
    if reason ~= 'expired' and reason ~= 'depleted' then return end
    if state.ctx and state.ctx.rewardSpawned then return end
    if state.ctx then state.ctx.rewardSpawned = true end
    if not state.location then return end

    local rewardId = state.id .. ':reward'
    local cfg = Config.AirdropCrash
    local items = CXE_Loot.GenerateLoot(cfg.lootTable, cfg.itemsPerCrate)
    local rewardCoords = vector3(state.location.x, state.location.y, state.location.z)

    CXE_Loot.RegisterContainer(rewardId, items, 'Crash Salvage', function(containerId)
        CXE_Loot.UnregisterContainer(rewardId)
        CXE_UnregisterSharedRewardCrate(rewardId)
        exports['corex-core']:BroadcastNearby(
            rewardCoords,
            1000.0,
            'corex-events:client:crashRewardExpired',
            rewardId
        )
    end, {
        consumeOnClose = true,
        coords = rewardCoords,
    })

    CXE_RegisterSharedRewardCrate(rewardId, {
        model = 'prop_box_ammo04a',
        coords = rewardCoords,
        center = rewardCoords,
        heading = 0.0,
        revealRadius = Config.AirdropCrash.radius,
        blipLabel = 'Crash Cargo',
        blipColor = 17,
        syncRadius = 1000.0,
        target = {
            text = '[E] Search Crash Cargo',
            icon = 'fa-box-open',
            distance = 3.0,
            event = 'corex-events:client:crash_searchCargo',
            data = { crateId = rewardId },
        },
    })

    exports['corex-core']:BroadcastNearby(
        rewardCoords,
        1000.0,
        'corex-events:client:crashReward',
        rewardId,
        { location = { x = state.location.x, y = state.location.y, z = state.location.z } }
    )

    CXE_Debug('Info', 'Crash reward spawned: ' .. rewardId)
end

CreateThread(function()
    while not CXE_RegisterHandler do Wait(100) end
    CXE_RegisterHandler('airdrop_crash', handler)
end)
