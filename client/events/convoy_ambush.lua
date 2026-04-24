local spawnedEntities = {}
local rewardCrates = {}
local visualsSpawnedByEvent = {}
local zoneBlip = nil
local markerBlip = nil

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

local function SearchConvoyCargo(entity, data)
    local Corex = CXEC_GetCorex()
    if not Corex then return end
    if not Corex.Functions.IsDead(Corex.Functions.GetPed()) then
        TriggerServerEvent('corex-loot:server:requestContainer', data.crateId)
    end
end

RegisterNetEvent('corex-events:client:convoy_searchCargo', function(entity, data)
    SearchConvoyCargo(entity, data)
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
    zoneBlip = CreateEventRadiusBlip(coords, Config.ConvoyAmbush.radius, 5, 80)

    markerBlip = CreateEventBlip(coords, {
        sprite = 67,
        color = 5,
        scale = 1.0,
        flash = true,
        flashInterval = 500,
        label = 'Convoy Ambush - ' .. (state.locationName or 'Unknown'),
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

    local cfg = Config.ConvoyAmbush

    local function LoadAndCreateVehicle(modelName, x, y, z, heading)
        local hash = GetHashKey(modelName)
        RequestModel(hash)
        local attempts = 0
        while not HasModelLoaded(hash) and attempts < 50 do
            Wait(100)
            attempts = attempts + 1
        end
        if not HasModelLoaded(hash) then return nil end
        local veh = CreateVehicle(hash, x, y, z, heading, false, false)
        SetModelAsNoLongerNeeded(hash)
        if veh and veh ~= 0 then
            SetEntityAsMissionEntity(veh, true, true)
            SetVehicleEngineOn(veh, false, false, true)
            SetVehicleDoorsLocked(veh, 2)
            return veh
        end
        return nil
    end

    local heading = (state and state.ctx and state.ctx.heading)
        or (cfg.routes and cfg.routes[1] and cfg.routes[1].heading or 0.0)

    local rightHeading = math.rad(heading + 90.0)
    local spawnX = loc.x + math.cos(rightHeading) * 3.5
    local spawnY = loc.y + math.sin(rightHeading) * 3.5
    local cargoVeh = LoadAndCreateVehicle(cfg.vehicles.cargo, spawnX, spawnY, loc.z, heading)
    if cargoVeh then
        SetVehicleDoorOpen(cargoVeh, 2, false, false)
        SetVehicleDoorOpen(cargoVeh, 3, false, false)
        SetVehicleDoorOpen(cargoVeh, 5, false, false)
        spawnedEntities[#spawnedEntities + 1] = cargoVeh
    end

    if state.description then
        Corex.Functions.Notify('Military convoy ambushed nearby! Check your map.', 'error', 6000)
    end
end

local function SpawnConvoyZombies(eventId, data)
    local count  = data.count or 12
    local spread = data.spread or 25.0

    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local dist  = math.random() * spread
        local x = data.location.x + math.cos(angle) * dist
        local y = data.location.y + math.sin(angle) * dist
        local z = data.location.z

        local ok, spawned = pcall(function()
            return exports['corex-zombies']:SpawnZombie(vector3(x, y, z))
        end)
    end
end

RegisterNetEvent('corex-events:client:convoySpawn', function(eventId, data)
    SpawnConvoyZombies(eventId, data)
end)

RegisterNetEvent('corex-events:client:convoyReward', function(rewardId, data)
    if CXEC_GetSharedRewardCrateContext(rewardId) then
        rewardCrates[rewardId] = true
        return
    end

    rewardCrates[rewardId] = true
    CXEC_RequestSharedRewardCrate(rewardId)
end)

RegisterNetEvent('corex-events:client:convoyRewardExpired', function(rewardId)
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
    CXEC_RegisterHandler('convoy_ambush', handler)
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
