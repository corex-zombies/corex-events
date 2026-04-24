local spawnedEntities = {}
local rewardCrates = {}
local survivorPeds = {}
local survivorSpawnedByEvent = {}
local zoneBlip = nil
local markerBlip = nil
local SpawnSurvivorPeds

local function CreateEventRadiusBlip(coords, radius, color, alpha)
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(blip, color)
    SetBlipAlpha(blip, alpha or 80)
    SetBlipCategory(blip, 10)
    SetBlipDisplay(blip, 6)
    return blip
end

local function CreateEventBlip(coords, options)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, options.sprite)
    SetBlipColour(blip, options.color)
    SetBlipScale(blip, options.scale or 1.0)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 10)
    SetBlipDisplay(blip, 6)
    if options.flash then
        SetBlipFlashes(blip, true)
        if options.flashInterval then
            SetBlipFlashInterval(blip, options.flashInterval)
        end
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(options.label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function ClaimSurvivorGift(entity, data)
    local Corex = CXEC_GetCorex()
    if not Corex then return end
    if not Corex.Functions.IsDead(Corex.Functions.GetPed()) then
        TriggerServerEvent('corex-loot:server:requestContainer', data.crateId)
    end
end

RegisterNetEvent('corex-events:client:survivor_claimGift', function(entity, data)
    ClaimSurvivorGift(entity, data)
end)

local function ClearEntities()
    for _, e in ipairs(spawnedEntities) do
        if type(e) == 'table' and e.prop then
            CXEC_CleanupRewardCrate(e)
        elseif DoesEntityExist(e) then
            pcall(function() exports['corex-core']:RemoveTarget(e) end)
            DeleteEntity(e)
        end
    end
    spawnedEntities = {}
    for _, p in ipairs(survivorPeds) do
        if DoesEntityExist(p) then DeleteEntity(p) end
    end
    survivorPeds = {}
    survivorSpawnedByEvent = {}
end

local handler = {}

function handler.start(state)
    local loc = state.location
    if not loc then return end

    local coords = vector3(loc.x, loc.y, loc.z)
    zoneBlip = CreateEventRadiusBlip(coords, Config.SurvivorRescue.radius, 2, 80)

    markerBlip = CreateEventBlip(coords, {
        sprite = 480,
        color = 2,
        scale = 1.0,
        flash = true,
        flashInterval = 500,
        label = 'Survivor Rescue - ' .. (state.locationName or 'Unknown'),
    })

    if state.spawned then
        SpawnSurvivorPeds(state.id, loc)
    end
end

function handler.update(state, patch)
    if not patch.spawned then return end
    if state.location then
        SpawnSurvivorPeds(state.id, state.location)
    end
end

function SpawnSurvivorPeds(eventId, loc)
    local Corex = CXEC_GetCorex()
    if not Corex then return end
    if not eventId or survivorSpawnedByEvent[eventId] then return end

    local models = Config.SurvivorRescue.survivorModels
    if not models or #models == 0 then return end

    survivorSpawnedByEvent[eventId] = true
    local count = math.min(3, #models)
    for i = 1, count do
        local model = models[((i - 1) % #models) + 1]
        local hash = GetHashKey(model)
        RequestModel(hash)
        local waitAttempts = 0
        while not HasModelLoaded(hash) and waitAttempts < 50 do
            Wait(100)
            waitAttempts = waitAttempts + 1
        end
        if HasModelLoaded(hash) then
            local angle = (i / count) * math.pi * 2
            local x = loc.x + math.cos(angle) * 3.0
            local y = loc.y + math.sin(angle) * 3.0
            local heading = (i * 120.0) % 360.0
            local ped = CreatePed(4, hash, x, y, loc.z, heading, false, false)
            if ped and ped ~= 0 then
                SetEntityAsMissionEntity(ped, true, true)
                SetEntityInvincible(ped, true)
                SetEntityProofs(ped, true, true, true, true, true, true, true, true)
                SetPedCanRagdoll(ped, false)
                SetPedDiesWhenInjured(ped, false)
                SetPedSuffersCriticalHits(ped, false)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedFleeAttributes(ped, 0, false)
                SetPedCanPlayAmbientAnims(ped, true)
                SetPedCanEvasiveDive(ped, false)
                SetPedCanBeTargetted(ped, false)
                SetEntityHealth(ped, GetEntityMaxHealth(ped))
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
                survivorPeds[#survivorPeds + 1] = ped
            end
        end
    end
end

RegisterNetEvent('corex-events:client:survivorSpawn', function(eventId, data)
    local Corex = CXEC_GetCorex()
    if not Corex then return end

    local loc = data.location
    SpawnSurvivorPeds(eventId, loc)

    local cfg = Config.SurvivorRescue
    local waveCount = math.random(cfg.zombiesPerWave.min, cfg.zombiesPerWave.max)
    for _ = 1, waveCount do
        local angle = math.random() * math.pi * 2
        local dist  = math.random(15.0, cfg.radius)
        local x = loc.x + math.cos(angle) * dist
        local y = loc.y + math.sin(angle) * dist
        pcall(function()
            exports['corex-zombies']:SpawnZombie(vector3(x, y, loc.z))
        end)
    end

    Corex.Functions.Notify('Survivors found! Protect them from incoming waves!', 'warning', 6000)
end)

RegisterNetEvent('corex-events:client:survivorWave', function(eventId, data)
    local Corex = CXEC_GetCorex()
    if not Corex then return end

    local state = ActiveEventsC[eventId]
    if not state or not state.location then return end

    local loc = state.location
    local count = data.count or 6
    local spread = data.spread or 30.0

    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local dist  = math.random(spread * 0.5, spread)
        local x = loc.x + math.cos(angle) * dist
        local y = loc.y + math.sin(angle) * dist
        pcall(function()
            exports['corex-zombies']:SpawnZombie(vector3(x, y, loc.z))
        end)
    end

    Corex.Functions.Notify(('Wave %d/%d incoming!'):format(data.wave, Config.SurvivorRescue.zombieWaves), 'error', 4000)
end)

RegisterNetEvent('corex-events:client:survivorReward', function(rewardId, data)
    if not CXEC_GetSharedRewardCrateContext(rewardId) then
        rewardCrates[rewardId] = true
        CXEC_RequestSharedRewardCrate(rewardId)
    else
        rewardCrates[rewardId] = true
    end

    local Corex = CXEC_GetCorex()
    if not Corex then return end
    for _, p in ipairs(survivorPeds) do
        if DoesEntityExist(p) then
            ClearPedTasks(p)
            TaskStartScenarioInPlace(p, 'WORLD_HUMAN_CHEERING', 0, true)
        end
    end
end)

RegisterNetEvent('corex-events:client:survivorRewardExpired', function(rewardId)
    if not rewardCrates[rewardId] and not CXEC_GetSharedRewardCrateContext(rewardId) then return end
    CXEC_ClearSharedRewardCrate(rewardId)
    rewardCrates[rewardId] = nil
end)

function handler.stop(state, reason)
    if zoneBlip and DoesBlipExist(zoneBlip) then RemoveBlip(zoneBlip) zoneBlip = nil end
    if markerBlip and DoesBlipExist(markerBlip) then RemoveBlip(markerBlip) markerBlip = nil end
    ClearEntities()
end

CreateThread(function()
    while not CXEC_RegisterHandler do Wait(100) end
    CXEC_RegisterHandler('survivor_rescue', handler)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        ClearEntities()
        for rewardId in pairs(rewardCrates) do
            CXEC_ClearSharedRewardCrate(rewardId)
            rewardCrates[rewardId] = nil
        end
    end
end)
