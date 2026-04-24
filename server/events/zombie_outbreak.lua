local PendingRewards = {}
local REWARD_GRACE   = 300

local handler = {}

function handler.start(state)
    local zones = Config.ZombieOutbreak.zones
    local zone  = PickZoneNearPlayers(zones)
    state.location     = zone.coords
    state.locationName = zone.label

    local cfg = Config.ZombieOutbreak
    state.ctx = {
        radius        = cfg.radius,
        spread        = cfg.spawnSpread,
        count         = math.random(cfg.zombieCount.min, cfg.zombieCount.max),
        spawned       = false,
        hostSource    = nil,
        waitLogStamp  = 0,
    }

    CXE_Debug('Info', ('Outbreak scheduled آ· %s آ· %d zombies آ· drop in %ds'):format(
        zone.label, state.ctx.count, state.announceLead or 30))
end

function handler.tick(state)
    if state.ctx.spawned then return end
    if os.time() < state.dropAt then return end

    local host, distance = PickNearestPlayer(state.location, 600.0)
    if not host then
        if (os.time() - state.ctx.waitLogStamp) > 10 then
            CXE_Debug('Verbose', ('Outbreak %s آ· no player within 600m آ· waiting'):format(state.id))
            state.ctx.waitLogStamp = os.time()
        end
        return
    end

    local syncCfg = Config.Sync or {}
    local sharedOk, sharedHostOrError = false, nil

    if syncCfg.Enabled and syncCfg.SharedEventHordes then
        sharedOk, sharedHostOrError = exports['corex-zombies']:CreateSharedBatch(
            state.id,
            vector3(state.location.x, state.location.y, state.location.z),
            state.ctx.count,
            state.ctx.spread
        )

        if not sharedOk then
            CXE_Debug('Warn', ('Outbreak %s · shared batch failed (%s) · falling back to legacy host spawn'):format(
                state.id,
                tostring(sharedHostOrError)
            ))
        end
    end

    state.ctx.hostSource = sharedOk and sharedHostOrError or host
    state.ctx.spawned    = true

    if not sharedOk then
        TriggerClientEvent('corex-events:client:outbreakSpawn', host, state.id, {
            location = { x = state.location.x, y = state.location.y, z = state.location.z },
            spread   = state.ctx.spread,
            count    = state.ctx.count,
        })
    end

    CXE_BroadcastUpdate(state, { spawned = true })
    CXE_Debug('Info', ('Outbreak %s آ· host=%d آ· dist=%.0fm آ· spawning %d zombies%s'):format(
        state.id,
        state.ctx.hostSource,
        distance,
        state.ctx.count,
        sharedOk and ' [shared]' or ''
    ))
end

function handler.stop(state, reason)
    if reason ~= 'expired' and reason ~= 'cleared' then return end

    local rewardId = state.id .. ':reward'
    local cfg = Config.ZombieOutbreak.rewardCrate
    local items = CXE_Loot.GenerateLoot(cfg.lootTable, cfg.itemsPerCrate)
    local label = (state.label or 'Outbreak') .. ' آ· Reward'

    PendingRewards[rewardId] = {
        coords    = state.location,
        expiresAt = os.time() + REWARD_GRACE,
    }

    local outbreakCoords = vector3(state.location.x, state.location.y, state.location.z)

    CXE_Loot.RegisterContainer(rewardId, items, label, function(containerId)
        local cached = PendingRewards[containerId]
        local expCoords = cached and cached.coords or outbreakCoords
        CXE_UnregisterSharedRewardCrate(containerId)
        exports['corex-core']:BroadcastNearby(expCoords, 1500.0, 'corex-events:client:outbreakRewardExpired', containerId)
        PendingRewards[containerId] = nil
    end, {
        consumeOnClose = true,
        coords = outbreakCoords,
    })

    CXE_RegisterSharedRewardCrate(rewardId, {
        model = cfg.model or 'prop_box_ammo02a',
        coords = outbreakCoords,
        center = outbreakCoords,
        heading = cfg.heading or 0.0,
        revealRadius = (state.ctx and state.ctx.radius) or Config.ZombieOutbreak.radius,
        blipLabel = 'Outbreak Reward',
        blipColor = 2,
        syncRadius = 1500.0,
        target = {
            text = 'Claim Reward Crate',
            icon = 'fa-gift',
            distance = 2.2,
            event = 'corex-events:client:outbreak_claimReward',
            data = { rewardId = rewardId },
        },
    })

    exports['corex-core']:BroadcastNearby(
        outbreakCoords,
        1500.0,
        'corex-events:client:outbreakReward',
        rewardId,
        {
            location = { x = state.location.x, y = state.location.y, z = state.location.z },
            radius   = (state.ctx and state.ctx.radius) or Config.ZombieOutbreak.radius,
            reason   = reason,
        }
    )

    CXE_Debug('Info', ('Outbreak ended آ· %s آ· reward container %s registered (grace %ds)'):format(
        state.id, rewardId, REWARD_GRACE))
end

local function Dist(a, b) return #(a - b) end

function PickZoneNearPlayers(zones)
    local players = GetPlayers()
    if #players == 0 then return zones[math.random(1, #zones)] end

    local eligible = {}
    local closestFallback, closestDist = nil, 999999.0

    for _, zone in ipairs(zones) do
        local minDist = 999999.0
        for _, srcStr in ipairs(players) do
            local ped = GetPlayerPed(tonumber(srcStr))
            if ped and ped ~= 0 then
                local d = Dist(GetEntityCoords(ped), zone.coords)
                if d < minDist then minDist = d end
            end
        end
        if minDist >= 100.0 and minDist <= 1500.0 then
            eligible[#eligible + 1] = zone
        end
        if minDist < closestDist then
            closestDist = minDist
            closestFallback = zone
        end
    end

    if #eligible > 0 then
        return eligible[math.random(1, #eligible)]
    end
    return closestFallback or zones[math.random(1, #zones)]
end

function PickNearestPlayer(zoneCoords, maxDist)
    local best, bestDist = nil, maxDist or 500.0
    for _, srcStr in ipairs(GetPlayers()) do
        local src = tonumber(srcStr)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local d = Dist(GetEntityCoords(ped), zoneCoords)
            if d < bestDist then
                bestDist = d
                best = src
            end
        end
    end
    return best, bestDist
end

CreateThread(function()
    while true do
        Wait(30000)

        if next(PendingRewards) == nil then
            goto continue
        end

        local now = os.time()
        for id, reward in pairs(PendingRewards) do
            if now >= (reward.expiresAt or 0) then
                local expCoords = reward.coords or vector3(0, 0, 0)
                CXE_Loot.UnregisterContainer(id)
                CXE_UnregisterSharedRewardCrate(id)
                exports['corex-core']:BroadcastNearby(expCoords, 1500.0, 'corex-events:client:outbreakRewardExpired', id)
                PendingRewards[id] = nil
                CXE_Debug('Verbose', 'Reward crate grace expired: ' .. id)
            end
        end

        ::continue::
    end
end)

CreateThread(function()
    while not CXE_RegisterHandler do Wait(100) end
    CXE_RegisterHandler('zombie_outbreak', handler)
end)
