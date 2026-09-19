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
    local now=os.time()
    if now<state.dropAt then return end
    local cfg=Config.Extraction
    if not state.ctx.spawned then
        local accepted,host=CXE_SpawnHorde(state,'initial',state.ctx.zombieCount,cfg.zombieSpread)
        if not accepted then return end
        state.ctx.hostSource,state.ctx.spawned=host,true
        state.ctx.wave=1
        state.ctx.nextWaveAt=now+math.max(1,math.floor((cfg.holdTime or 120)/4))
        CXE_BroadcastUpdate(state,{spawned=true})
        return
    end
    if state.ctx.wave<=3 and now>=state.ctx.nextWaveAt then
        local phase='wave:'..state.ctx.wave
        if not CXE_SpawnHorde(state,phase,math.random(4,8),cfg.radius) then return end
        state.ctx.wave=state.ctx.wave+1
        state.ctx.nextWaveAt=now+math.max(1,math.floor((cfg.holdTime or 120)/4))
    end
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
