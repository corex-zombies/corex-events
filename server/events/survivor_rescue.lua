local handler = {}

local function IsHostAvailable(src)
    if not src then return false end
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0
end

local function PickNearbyHost(location, radius)
    for _, srcStr in ipairs(GetPlayers()) do
        local src = tonumber(srcStr)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local d = #(GetEntityCoords(ped) - location)
            if d < radius then return src end
        end
    end
    return nil
end

function handler.start(state)
    local locations = Config.SurvivorRescue.locations
    local loc  = locations[math.random(1, #locations)]
    state.location     = loc.coords
    state.locationName = loc.label

    local cfg = Config.SurvivorRescue
    state.ctx = {
        currentWave  = 0,
        totalWaves   = cfg.zombieWaves,
        waveSpawned  = false,
        hostSource   = nil,
        waitStamp    = 0,
        nextWaveAt   = nil,
        rewardSpawned = false,
    }

    CXE_Debug('Info', ('Survivor rescue · %s · %d waves · drop in %ds'):format(
        loc.label, cfg.zombieWaves, state.announceLead or 20))
end

function handler.tick(state)
    local now=os.time()
    if now<state.dropAt then return end
    local cfg=Config.SurvivorRescue
    if not state.ctx.spawned then
        local host=PickNearbyHost(state.location,600)
        if not host then return end
        state.ctx.spawned,state.ctx.hostSource=true,host
        state.ctx.currentWave,state.ctx.nextWaveAt=1,now+5
        TriggerClientEvent('corex-events:client:survivorSpawn',host,state.id,{
            location={x=state.location.x,y=state.location.y,z=state.location.z}})
        CXE_BroadcastUpdate(state,{spawned=true})
        return
    end
    if state.ctx.currentWave>state.ctx.totalWaves or now<state.ctx.nextWaveAt then return end
    local wave=state.ctx.currentWave
    local count=math.random(cfg.zombiesPerWave.min,cfg.zombiesPerWave.max)
    if not CXE_SpawnHorde(state,'wave:'..wave,count,cfg.radius) then return end
    TriggerClientEvent('corex-events:client:survivorWave',-1,state.id,{wave=wave})
    state.ctx.currentWave=wave+1
    state.ctx.nextWaveAt=now+math.max(1,math.floor(cfg.waveInterval/1000))
    state.ctx.waveSpawned=true
end

function handler.stop(state, reason)
    CXE_ClearHordes(state)
    CXE_Loot.UnregisterContainer(state.id .. ':reward')
    CXE_UnregisterSharedRewardCrate(state.id .. ':reward')
    if reason ~= 'expired' and reason ~= 'cleared' then return end
    if state.ctx and state.ctx.rewardSpawned then return end
    if state.ctx then state.ctx.rewardSpawned = true end
    if not state.location then return end

    local rewardId = state.id .. ':reward'
    local cfg = Config.SurvivorRescue
    local items = CXE_Loot.GenerateLoot(cfg.rewardLoot, cfg.itemsPerReward)
    local rewardCoords = vector3(state.location.x, state.location.y, state.location.z)

    CXE_Loot.RegisterContainer(rewardId, items, 'Survivor Reward', function(containerId)
        CXE_Loot.UnregisterContainer(rewardId)
        CXE_UnregisterSharedRewardCrate(rewardId)
        exports['corex-core']:BroadcastNearby(
            rewardCoords,
            1000.0,
            'corex-events:client:survivorRewardExpired',
            rewardId
        )
    end, {
        consumeOnClose = true,
        coords = rewardCoords,
    })

    CXE_RegisterSharedRewardCrate(rewardId, {
        model = 'prop_box_ammo02a',
        coords = rewardCoords,
        center = rewardCoords,
        heading = 0.0,
        revealRadius = Config.SurvivorRescue.radius,
        blipLabel = 'Survivor Gift',
        blipColor = 2,
        syncRadius = 1000.0,
        target = {
            text = '[E] Survivor Gift',
            icon = 'fa-gift',
            distance = 3.0,
            event = 'corex-events:client:survivor_claimGift',
            data = { crateId = rewardId },
        },
    })

    exports['corex-core']:BroadcastNearby(
        rewardCoords,
        1000.0,
        'corex-events:client:survivorReward',
        rewardId,
        { location = { x = state.location.x, y = state.location.y, z = state.location.z } }
    )

    CXE_Debug('Info', 'Survivor rescue reward: ' .. rewardId)
end

CreateThread(function()
    while not CXE_RegisterHandler do Wait(100) end
    CXE_RegisterHandler('survivor_rescue', handler)
end)
