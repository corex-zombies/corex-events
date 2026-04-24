local spawnedEntities = {}
local rewardCrates = {}
local visualsSpawnedByEvent = {}
local zoneBlip = nil
local markerBlip = nil
local DEBRIS_MODELS = {
    'prop_roadcone01a',
    'prop_rubble_03a',
    'prop_rubble_04a',
    'prop_air_luggage_01a',
    'prop_box_ammo04a',
    'prop_metal_crate_01a',
    'prop_container_02a',
}

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

local function SearchCrashCargo(entity, data)
    local Corex = CXEC_GetCorex()
    if not Corex then return end
    if not Corex.Functions.IsDead(Corex.Functions.GetPed()) then
        TriggerServerEvent('corex-loot:server:requestContainer', data.crateId)
    end
end

RegisterNetEvent('corex-events:client:crash_searchCargo', function(entity, data)
    SearchCrashCargo(entity, data)
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
    visualsSpawnedByEvent = {}
end

local handler = {}

function handler.start(state)
    local loc = state.location
    if not loc then return end

    local coords = vector3(loc.x, loc.y, loc.z)
    zoneBlip = CreateEventRadiusBlip(coords, Config.AirdropCrash.radius, 17, 80)

    markerBlip = CreateEventBlip(coords, {
        sprite = 487,
        color = 17,
        scale = 1.0,
        flash = true,
        flashInterval = 500,
        label = 'Crash Site - ' .. (state.locationName or 'Unknown'),
    })

    if state.spawned and handler.update then
        handler.update(state, { spawned = true })
    end
end

function handler.update(state, patch)
    if not patch.spawned then return end
    if visualsSpawnedByEvent[state.id] then return end

    local Corex = CXEC_GetCorex()
    if not Corex then return end

    local loc = state.location
    if not loc then return end
    visualsSpawnedByEvent[state.id] = true

    local count = state.ctx and state.ctx.debris or 6
    local center = vector3(loc.x, loc.y, loc.z)

    for i = 1, count do
        local angle = (i / count) * math.pi * 2 + math.random() * 0.5
        local dist  = math.random(3.0, 20.0)
        local x = loc.x + math.cos(angle) * dist
        local y = loc.y + math.sin(angle) * dist
        local model = DEBRIS_MODELS[math.random(1, #DEBRIS_MODELS)]

        local prop = Corex.Functions.SpawnProp(model, vector3(x, y, loc.z), {
            placeOnGround = true, networked = false, freeze = true
        })
        if prop then
            SetEntityHeading(prop, math.random() * 360.0)
            spawnedEntities[#spawnedEntities + 1] = prop
        end
    end

    local firePos = vector3(loc.x + 5.0, loc.y, loc.z)
    local fireProp = Corex.Functions.SpawnProp('prop_beach_fire', firePos, {
        placeOnGround = true, networked = false, freeze = true
    })
    if fireProp then spawnedEntities[#spawnedEntities + 1] = fireProp end

    Corex.Functions.Notify('Cargo plane crash detected! High-value loot in the wreckage.', 'warning', 6000)
end

local function SpawnCrashZombies(eventId, data)
    local count = data.count or 10
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local dist  = math.random() * (data.spread or 40.0)
        local x = data.location.x + math.cos(angle) * dist
        local y = data.location.y + math.sin(angle) * dist

        pcall(function()
            exports['corex-zombies']:SpawnZombie(vector3(x, y, data.location.z))
        end)
    end
end

RegisterNetEvent('corex-events:client:crashSpawn', function(eventId, data)
    SpawnCrashZombies(eventId, data)
end)

RegisterNetEvent('corex-events:client:crashReward', function(rewardId, data)
    if CXEC_GetSharedRewardCrateContext(rewardId) then
        rewardCrates[rewardId] = true
        return
    end

    rewardCrates[rewardId] = true
    CXEC_RequestSharedRewardCrate(rewardId)
end)

RegisterNetEvent('corex-events:client:crashRewardExpired', function(rewardId)
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
    CXEC_RegisterHandler('airdrop_crash', handler)
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
