local handler = {}

function handler.start(state)
    local routes = Config.ConvoyAmbush.routes
    local route  = routes[math.random(1, #routes)]
    state.location     = route.start
    state.locationName = route.label

    local cfg = Config.ConvoyAmbush
    state.ctx = {
        zombieCount = math.random(cfg.zombieCount.min, cfg.zombieCount.max),
        spawned     = false,
        hostSource  = nil,
        waitStamp   = 0,
        heading     = route.heading or 0.0,
        rewardSpawned = false,
    }

    CXE_Debug('Info', ('Convoy ambush · %s · %d zombies · drop in %ds'):format(
        route.label, state.ctx.zombieCount, state.announceLead or 45))
end

function handler.tick(state)
    if state.ctx.spawned or os.time()<state.dropAt then return end
    local accepted,host=CXE_SpawnHorde(state,'initial',state.ctx.zombieCount,Config.ConvoyAmbush.zombieSpread)
    if not accepted then return end
    state.ctx.hostSource,state.ctx.spawned=host,true
    -- All viewers create local scenery from the public event context.
    CXE_BroadcastUpdate(state,{spawned=true})
end

function handler.stop(state, reason)
    CXE_ClearHordes(state)
    CXE_Loot.UnregisterContainer(state.id .. ':reward')
    CXE_UnregisterSharedRewardCrate(state.id .. ':reward')
    if reason ~= 'expired' and reason ~= 'depleted' then return end
    if state.ctx and state.ctx.rewardSpawned then return end
    if state.ctx then state.ctx.rewardSpawned = true end
    if not state.location then return end

    local rewardId = state.id .. ':reward'
    local cfg = Config.ConvoyAmbush
    local items = CXE_Loot.GenerateLoot(cfg.lootTable, cfg.itemsPerCrate)
    local rewardCoords = vector3(state.location.x, state.location.y, state.location.z)

    CXE_Loot.RegisterContainer(rewardId, items, 'Convoy Salvage', function(containerId)
        CXE_Loot.UnregisterContainer(rewardId)
        CXE_UnregisterSharedRewardCrate(rewardId)
        exports['corex-core']:BroadcastNearby(
            rewardCoords,
            1000.0,
            'corex-events:client:convoyRewardExpired',
            rewardId
        )
    end, {
        consumeOnClose = true,
        coords = rewardCoords,
    })

    CXE_RegisterSharedRewardCrate(rewardId, {
        model = 'prop_mil_crate_01',
        coords = rewardCoords,
        center = rewardCoords,
        heading = 0.0,
        revealRadius = Config.ConvoyAmbush.radius,
        blipLabel = 'Convoy Cargo',
        blipColor = 5,
        syncRadius = 1000.0,
        target = {
            text = '[E] Search Convoy Cargo',
            icon = 'fa-box',
            distance = 3.0,
            event = 'corex-events:client:convoy_searchCargo',
            data = { crateId = rewardId },
        },
    })

    exports['corex-core']:BroadcastNearby(
        rewardCoords,
        1000.0,
        'corex-events:client:convoyReward',
        rewardId,
        { location = { x = state.location.x, y = state.location.y, z = state.location.z } }
    )

    CXE_Debug('Info', 'Convoy reward spawned: ' .. rewardId)
end

CreateThread(function()
    while not CXE_RegisterHandler do Wait(100) end
    CXE_RegisterHandler('convoy_ambush', handler)
end)
