local spawnedEntities = {}
local rewardCrates = {}
local spawnedBlips = {}
local visualsSpawnedByEvent = {}
local zoneBlip = nil
local countdownShown = false

local function CreateEventRadiusBlip(coords, radius, color, alpha)
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(blip, color)
    SetBlipAlpha(blip, alpha or 100)
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

local function OpenExtractionCrate(entity, data)
    local Corex = CXEC_GetCorex()
    if not Corex then return end
    if not Corex.Functions.IsDead(Corex.Functions.GetPed()) then
        TriggerServerEvent('corex-loot:server:requestContainer', data.crateId)
    end
end

RegisterNetEvent('corex-events:client:extraction_openCrate', function(entity, data)
    OpenExtractionCrate(entity, data)
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
    for _, b in ipairs(spawnedBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    spawnedBlips = {}
    visualsSpawnedByEvent = {}
    if zoneBlip and DoesBlipExist(zoneBlip) then RemoveBlip(zoneBlip) end
    zoneBlip = nil
    countdownShown = false
end

local handler = {}

function handler.start(state)
    local loc = state.location
    if not loc then return end

    local cfg = Config.Extraction
    local coords = vector3(loc.x, loc.y, loc.z)

    zoneBlip = CreateEventRadiusBlip(coords, cfg.radius, 5, 100)

    local markerBlip = CreateEventBlip(coords, {
        sprite = 43,
        color = 5,
        scale = 1.2,
        flash = true,
        flashInterval = 500,
        label = 'Extraction Point',
    })
    if markerBlip then
        spawnedBlips[#spawnedBlips + 1] = markerBlip
    end

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

    local cfg = Config.Extraction
    local center = vector3(loc.x, loc.y, loc.z)

    Corex.Functions.Notify('Extraction point active! Defend the zone until the helicopter arrives!', 'error', 7000)

    CreateThread(function()
        local holdSec = cfg.holdTime or 120
        for i = holdSec, 1, -1 do
            if not ActiveEventsC[state.id] then break end
            if i <= 10 or i % 30 == 0 then
                local mins = math.floor(i / 60)
                local secs = i % 60
                local timeStr = mins > 0 and ('%dm %ds'):format(mins, secs) or ('%ds'):format(secs)
                Corex.Functions.Notify(('Extraction in %s - hold the zone!'):format(timeStr), 'warning', 3000)
            end
            Wait(1000)
        end
    end)
end

local function SpawnExtractionZombies(eventId, data)
    local count = data.count or 20
    local spread = data.spread or 50.0
    for _ = 1, count do
        local angle = math.random() * math.pi * 2
        local dist  = math.random(spread * 0.3, spread)
        local x = data.location.x + math.cos(angle) * dist
        local y = data.location.y + math.sin(angle) * dist
        pcall(function()
            exports['corex-zombies']:SpawnZombie(vector3(x, y, data.location.z))
        end)
    end
end

RegisterNetEvent('corex-events:client:extractionSpawn', function(eventId, data)
    SpawnExtractionZombies(eventId, data)

    CreateThread(function()
        local cfg = Config.Extraction
        for wave = 1, 3 do
            Wait(math.floor((cfg.holdTime or 120) * 1000 / 4))
            if not ActiveEventsC[eventId] then break end
            local extra = math.random(4, 8)
            local loc = data.location
            for _ = 1, extra do
                local angle = math.random() * math.pi * 2
                local dist  = math.random(20.0, cfg.radius)
                local x = loc.x + math.cos(angle) * dist
                local y = loc.y + math.sin(angle) * dist
                pcall(function()
                    exports['corex-zombies']:SpawnZombie(vector3(x, y, loc.z))
                end)
            end
        end
    end)
end)

RegisterNetEvent('corex-events:client:extractionReward', function(rewardId, data)
    if not CXEC_GetSharedRewardCrateContext(rewardId) then
        rewardCrates[rewardId] = true
        CXEC_RequestSharedRewardCrate(rewardId)
    else
        rewardCrates[rewardId] = true
    end

    local Corex = CXEC_GetCorex()
    if not Corex then return end
    Corex.Functions.Notify('Extraction complete! Helicopter is inbound!', 'success', 5000)
end)

RegisterNetEvent('corex-events:client:extractionRewardExpired', function(rewardId)
    if not rewardCrates[rewardId] and not CXEC_GetSharedRewardCrateContext(rewardId) then return end
    CXEC_ClearSharedRewardCrate(rewardId)
    rewardCrates[rewardId] = nil
end)

function handler.stop(state, reason)
    ClearEntities()
end

CreateThread(function()
    while not CXEC_RegisterHandler do Wait(100) end
    CXEC_RegisterHandler('extraction', handler)
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
