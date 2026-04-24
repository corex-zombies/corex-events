-- ═══════════════════════════════════════════════════════════════
-- Zombie Outbreak · client handler
-- Blip + radius ring + warning fog + spawn coordination + reward crate.
-- ═══════════════════════════════════════════════════════════════

local State       = {}   -- eventId → { blip, radiusBlip, ptfx, hasSpawned }
local RewardProps = {}   -- eventId → { prop, blip, thread } — kept past event end
                         -- so players can still claim after duration expires.

local function ClaimOutbreakReward(entity, data)
    TriggerServerEvent('corex-loot:server:requestContainer', data.rewardId)
end

RegisterNetEvent('corex-events:client:outbreak_claimReward', function(entity, data)
    ClaimOutbreakReward(entity, data)
end)

-- Safe vector3 parse (handles both vector3 and plain table) ───
local function ToVec3(loc)
    if not loc then return nil end
    return vector3(loc.x or loc[1] or 0.0, loc.y or loc[2] or 0.0, loc.z or loc[3] or 0.0)
end

-- Blip helpers ────────────────────────────────────────────────
local function MakeBlip(coords, label, color)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 436)          -- biohazard-ish
    SetBlipColour(blip, color or 1)   -- 1 = red
    SetBlipScale(blip, 1.1)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 10)
    SetBlipDisplay(blip, 6)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Outbreak Zone')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function MakeRadiusBlip(coords, radius)
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(blip, 1)            -- red
    SetBlipAlpha(blip, 64)
    return blip
end

-- Model helpers ───────────────────────────────────────────────
local function LoadModel(model)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelInCdimage(hash) then return nil end
    -- TODO: Move to Corex.Functions.LoadModel once implemented
    -- TEMPORARY: using FiveM native directly
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(10)
        if GetGameTimer() - t > 5000 then return nil end
    end
    return hash
end

local function GroundZ(x, y, zGuess)
    local ok, z = GetGroundZFor_3dCoord(x, y, zGuess or 500.0, false)
    if ok then return z end
    return zGuess or 30.0
end

-- Warning particle effect (red fog) ───────────────────────────
local function StartWarningFog(coords)
    local asset = 'scr_ornate_heist'
    RequestNamedPtfxAsset(asset)
    local t = GetGameTimer()
    while not HasNamedPtfxAssetLoaded(asset) do
        Wait(10)
        if GetGameTimer() - t > 3000 then return nil end
    end
    UseParticleFxAssetNextCall(asset)
    local gz = GroundZ(coords.x, coords.y, coords.z + 20.0)
    local fx = StartParticleFxLoopedAtCoord(
        'scr_heist_ornate_smoke',
        coords.x, coords.y, gz + 0.5,
        0.0, 0.0, 0.0,
        3.5, false, false, false, false
    )
    return fx
end

-- Handler ─────────────────────────────────────────────────────
local handler = {}

function handler.start(state, meta)
    local coords = ToVec3(state.location)
    if not coords then
        CXEC_Debug('Error', 'Outbreak has no location: ' .. (state.id or '?'))
        return
    end
    local radius = (Config.ZombieOutbreak and Config.ZombieOutbreak.radius) or 80.0
    CXEC_Debug('Info', ('Outbreak announce · id=%s · %.1f, %.1f, %.1f'):format(
        state.id, coords.x, coords.y, coords.z))

    State[state.id] = {
        hasSpawned = false,
        hasReward  = false,
    }

    State[state.id].blip       = MakeBlip(coords, state.label or 'Outbreak Zone', 1)
    State[state.id].radiusBlip = MakeRadiusBlip(coords, radius)

    -- Warning fog during announce phase
    State[state.id].ptfx = StartWarningFog(coords)

    -- Flashing blip during announce
    local blip = State[state.id].blip
    if blip and DoesBlipExist(blip) then
        SetBlipFlashes(blip, true)
        SetBlipFlashInterval(blip, 400)
        CreateThread(function()
            Wait((state.announceLead or 30) * 1000)
            if DoesBlipExist(blip) then SetBlipFlashes(blip, false) end
        end)
    end

    -- If joining mid-event, sync spawned state
    if state.spawned then
        State[state.id].hasSpawned = true
        if State[state.id].ptfx then
            StopParticleFxLooped(State[state.id].ptfx, false)
            State[state.id].ptfx = nil
        end
    end
end

function handler.update(state, patch)
    if patch and patch.spawned and State[state.id] and not State[state.id].hasSpawned then
        State[state.id].hasSpawned = true
        -- Dim the fog a bit once zombies are live (fog was warning, now it's combat)
        local s = State[state.id]
        if s.ptfx then
            StopParticleFxLooped(s.ptfx, false)
            s.ptfx = nil
        end
    end
end

function handler.stop(state, reason)
    local s = State[state.id]
    if not s then return end

    -- Tear down outbreak-phase visuals only. Reward crate is separate and
    -- may have just been spawned by corex-events:client:outbreakReward —
    -- that lives in RewardProps and outlives this stop().
    if s.blip       and DoesBlipExist(s.blip)       then RemoveBlip(s.blip) end
    if s.radiusBlip and DoesBlipExist(s.radiusBlip) then RemoveBlip(s.radiusBlip) end
    if s.ptfx                                        then StopParticleFxLooped(s.ptfx, false) end

    State[state.id] = nil
end

-- Server → host client: spawn the horde ───────────────────────
RegisterNetEvent('corex-events:client:outbreakSpawn', function(eventId, data)
    if not data then return end
    local center = ToVec3(data.location)
    if not center then return end
    local spread = data.spread or 55.0
    local count  = data.count  or 20

    CXEC_Debug('Info', ('Outbreak host · spawning %d zombies at %.1f, %.1f, %.1f'):format(
        count, center.x, center.y, center.z))

    CreateThread(function()
        RequestCollisionAtCoord(center.x, center.y, center.z)
        local localCorex = exports['corex-core']:GetCoreObject()
        local localPed = (localCorex and localCorex.Functions and localCorex.Functions.GetPed) and localCorex.Functions.GetPed() or 0
        local t0 = GetGameTimer()
        while localPed ~= 0 and not HasCollisionLoadedAroundEntity(localPed) and (GetGameTimer() - t0) < 2000 do
            Wait(50)
        end

        local spawned, failed = 0, 0
        for i = 1, count do
            local ang  = math.random() * 2 * math.pi
            local dist = math.random() * spread
            local x    = center.x + math.cos(ang) * dist
            local y    = center.y + math.sin(ang) * dist
            local z    = GroundZ(x, y, center.z + 20.0)

            local ok, ped = pcall(function()
                return exports['corex-zombies']:SpawnZombie(vector3(x, y, z + 0.3), nil)
            end)
            if ok and ped then
                spawned = spawned + 1
            else
                failed = failed + 1
                if failed <= 3 then
                    -- Only log the first few failures; avoid console spam
                    CXEC_Debug('Warn', ('SpawnZombie failed · err=%s'):format(tostring(ped)))
                end
            end

            Wait(math.random(150, 250))
        end

        CXEC_Debug('Info', ('Outbreak spawn complete · %d succeeded · %d failed'):format(
            spawned, failed))
    end)
end)

-- Server → all clients: spawn reward crate at outbreak center ─
RegisterNetEvent('corex-events:client:outbreakReward', function(eventId, data)
    if not data then return end
    if RewardProps[eventId] or CXEC_GetSharedRewardCrateContext(eventId) then
        RewardProps[eventId] = true
        return
    end

    RewardProps[eventId] = true
    CXEC_RequestSharedRewardCrate(eventId)
end)

-- Server → clients: reward grace expired — remove prop + blip
RegisterNetEvent('corex-events:client:outbreakRewardExpired', function(eventId)
    if not RewardProps[eventId] and not CXEC_GetSharedRewardCrateContext(eventId) then return end
    CXEC_ClearSharedRewardCrate(eventId)
    RewardProps[eventId] = nil
end)

-- Clean up reward props on resource stop as well
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(RewardProps) do
        CXEC_ClearSharedRewardCrate(id)
        RewardProps[id] = nil
    end
end)

-- Register with router ────────────────────────────────────────
CreateThread(function()
    while not CXEC_RegisterHandler do Wait(100) end
    CXEC_RegisterHandler('zombie_outbreak', handler)
end)
