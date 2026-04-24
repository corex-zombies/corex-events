-- ═══════════════════════════════════════════════════════════════
-- COREX Events · Client Main
-- Mirrors server state locally, dispatches event start/update/end
-- to per-event client handlers.
-- ═══════════════════════════════════════════════════════════════

local Corex = nil
SharedRewardCrates = SharedRewardCrates or {}

ActiveEventsC   = ActiveEventsC   or {}  -- id → public state
ClientHandlers  = ClientHandlers  or {}  -- type → { start, update, stop }

-- Debug ────────────────────────────────────────────────────────
local function Debug(level, msg)
    if not Config.Debug and level ~= 'Error' then return end
    local tag = ({ Error = '^1', Warn = '^3', Info = '^2', Verbose = '^5' })[level] or '^7'
    print(tag .. '[COREX-EVENTS] ' .. tostring(msg) .. '^0')
end
CXEC_Debug = Debug

-- Core ─────────────────────────────────────────────────────────
local function InitCorex()
    local attempts = 0
    while not Corex and attempts < 30 do
        local ok, result = pcall(function()
            return exports['corex-core']:GetCoreObject()
        end)
        if ok and result then
            Corex = result
            return true
        end
        attempts = attempts + 1
        Wait(1000)
    end
    return false
end
CXEC_GetCorex = function() return Corex end

-- Handler registry ─────────────────────────────────────────────
function CXEC_RegisterHandler(eventType, handler)
    ClientHandlers[eventType] = handler
    Debug('Info', 'Client handler: ' .. eventType)
end

if not CXEC_CreateEventBlip then
    local function ApplyCommonBlipSettings(blip, options)
        if not blip or blip == 0 then
            return nil
        end

        options = options or {}

        if options.sprite then SetBlipSprite(blip, options.sprite) end
        if options.color then SetBlipColour(blip, options.color) end
        if options.scale then SetBlipScale(blip, options.scale) end

        SetBlipAsShortRange(blip, options.shortRange == true)
        SetBlipCategory(blip, options.category or 10)
        SetBlipDisplay(blip, options.display or 6)

        if options.alpha then SetBlipAlpha(blip, options.alpha) end
        if options.flash then
            SetBlipFlashes(blip, true)
            if options.flashInterval then
                SetBlipFlashInterval(blip, options.flashInterval)
            end
        end

        if options.label then
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(options.label)
            EndTextCommandSetBlipName(blip)
        end

        return blip
    end

    function CXEC_CreateEventBlip(coords, options)
        if not coords then return nil end
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        return ApplyCommonBlipSettings(blip, options)
    end

    function CXEC_CreateEventRadiusBlip(coords, radius, options)
        if not coords or not radius then return nil end
        local blip = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
        return ApplyCommonBlipSettings(blip, options)
    end
end

do
    local function EventPrint(message)
        print('^3[COREX-EVENTS][CRATE]^7 ' .. tostring(message))
    end

    local function ReportCrateIssue(eventId, stage, message)
        EventPrint(('event=%s stage=%s %s'):format(
            tostring(eventId or 'unknown'),
            tostring(stage or 'unknown'),
            tostring(message or 'unknown')
        ))
        TriggerServerEvent('corex-events:server:clientCrateIssue', eventId or 'unknown', stage or 'unknown', tostring(message or 'unknown'))
    end
    CXEC_ReportCrateIssue = ReportCrateIssue

    local function LoadNamedPtfx(asset, timeoutMs)
        if HasNamedPtfxAssetLoaded(asset) then return true end
        RequestNamedPtfxAsset(asset)
        local startedAt = GetGameTimer()
        while not HasNamedPtfxAssetLoaded(asset) do
            Wait(10)
            if GetGameTimer() - startedAt > (timeoutMs or 3000) then
                return false
            end
        end
        return true
    end

    local function LoadModelHash(model, timeoutMs)
        local hash = type(model) == 'string' and GetHashKey(model) or model
        if not hash or not IsModelInCdimage(hash) then return nil end
        if HasModelLoaded(hash) then return hash end

        RequestModel(hash)
        local startedAt = GetGameTimer()
        while not HasModelLoaded(hash) do
            Wait(10)
            if GetGameTimer() - startedAt > (timeoutMs or 5000) then
                return nil
            end
        end
        return hash
    end

    local function ResolveGroundZ(x, y, zGuess)
        local base = zGuess or 0.0
        local probeHeights = { base + 25.0, base + 50.0, base + 100.0, base + 250.0, 1000.0 }
        for _, probe in ipairs(probeHeights) do
            local found, groundZ = GetGroundZFor_3dCoord(x, y, probe, false)
            if found then return groundZ, true end
        end
        return base, false
    end

    local function ResolveModelBaseOffset(hash)
        local minDim, _ = GetModelDimensions(hash)
        return math.max(0.0, -(minDim.z or 0.0))
    end

    local function RequestGroundCollision(coords, passes)
        for _ = 1, (passes or 6) do
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            Wait(75)
        end
    end

    local function TryResolveSharedCrateEntity(netId, timeoutMs)
        if not netId or netId <= 0 then return nil end

        local deadline = GetGameTimer() + (timeoutMs or 8000)
        while GetGameTimer() < deadline do
            if NetworkDoesNetworkIdExist(netId) and NetworkDoesEntityExistWithNetworkId(netId) then
                local entity = NetToObj(netId)
                if entity and entity ~= 0 and DoesEntityExist(entity) then
                    return entity
                end
            end
            Wait(100)
        end

        return nil
    end

    local function TryDeleteSharedEntity(entity)
        if not entity or entity == 0 then return end

        CreateThread(function()
            if not DoesEntityExist(entity) then return end

            if NetworkGetEntityIsNetworked(entity) then
                local deadline = GetGameTimer() + 1000
                while DoesEntityExist(entity) and not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
                    NetworkRequestControlOfEntity(entity)
                    Wait(0)
                end
            end

            if DoesEntityExist(entity) then
                DeleteEntity(entity)
            end
        end)
    end

    local function SpawnLocalRewardObject(model, coords, eventId, networked)
        local hash = LoadModelHash(model)
        if not hash then
            ReportCrateIssue(eventId, 'invalid_model', ('model=%s is not available'):format(tostring(model)))
            return nil, nil
        end

        local isNetworked = networked == true
        local prop = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, isNetworked, isNetworked, false)
        if (not prop or prop == 0 or not DoesEntityExist(prop)) then
            prop = CreateObject(hash, coords.x, coords.y, coords.z, isNetworked, isNetworked, false)
        end
        SetModelAsNoLongerNeeded(hash)
        if not prop or prop == 0 or not DoesEntityExist(prop) then
            return nil, hash
        end

        SetEntityAsMissionEntity(prop, true, true)
        SetEntityVisible(prop, true, false)
        ResetEntityAlpha(prop)
        SetEntityCollision(prop, true, true)
        SetEntityDynamic(prop, false)
        FreezeEntityPosition(prop, false)

        if isNetworked then
            local netId = NetworkGetNetworkIdFromEntity(prop)
            if netId and netId ~= 0 then
                SetNetworkIdExistsOnAllMachines(netId, true)
                SetNetworkIdCanMigrate(netId, true)
            end
        end

        return prop, hash
    end

    local function SnapCrateToGround(prop, modelHash, targetCoords)
        if not prop or not DoesEntityExist(prop) then
            return false, nil, nil
        end

        local groundZ, foundGround = ResolveGroundZ(targetCoords.x, targetCoords.y, targetCoords.z + 20.0)
        local baseOffset = ResolveModelBaseOffset(modelHash)
        local snappedZ = (foundGround and groundZ or targetCoords.z) + baseOffset + 0.02

        FreezeEntityPosition(prop, false)
        SetEntityCollision(prop, true, true)
        SetEntityCoordsNoOffset(prop, targetCoords.x, targetCoords.y, snappedZ, false, false, false)
        PlaceObjectOnGroundProperly(prop)

        for _ = 1, 8 do
            Wait(50)
            RequestCollisionAtCoord(targetCoords.x, targetCoords.y, snappedZ)
            PlaceObjectOnGroundProperly(prop)
        end

        FreezeEntityPosition(prop, true)

        local finalCoords = GetEntityCoords(prop)
        local finalGroundZ, finalFound = ResolveGroundZ(finalCoords.x, finalCoords.y, finalCoords.z + 20.0)
        local finalGap = finalFound and (finalCoords.z - finalGroundZ) or 0.0

        if finalFound and finalGap > 3.0 then
            local forcedZ = finalGroundZ + baseOffset + 0.02
            SetEntityCoordsNoOffset(prop, targetCoords.x, targetCoords.y, forcedZ, false, false, false)
            PlaceObjectOnGroundProperly(prop)
            FreezeEntityPosition(prop, true)
            finalCoords = GetEntityCoords(prop)
        end

        return true, vector3(finalCoords.x, finalCoords.y, finalCoords.z), finalGap
    end

    local function StartCrateFlare(coords)
        local effectSets = {
            { asset = 'core', effect = 'exp_grd_flare', scale = 1.25 },
            { asset = 'scr_rcbarry2', effect = 'scr_clown_appears', scale = 1.8 },
        }

        for _, entry in ipairs(effectSets) do
            if LoadNamedPtfx(entry.asset) then
                UseParticleFxAssetNextCall(entry.asset)
                local handle = StartParticleFxLoopedAtCoord(
                    entry.effect,
                    coords.x, coords.y, coords.z + 0.3,
                    0.0, 0.0, 0.0,
                    entry.scale,
                    false, false, false, false
                )
                if handle and handle ~= 0 then return handle end
            end
        end

        return nil
    end

    local function CreateCrateBlip(coords, label, color, sprite, scale)
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, sprite or 478)
        SetBlipColour(blip, color or 2)
        SetBlipScale(blip, scale or 0.9)
        SetBlipFlashes(blip, true)
        SetBlipAsShortRange(blip, false)
        SetBlipCategory(blip, 10)
        SetBlipDisplay(blip, 6)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(label or 'Event Crate')
        EndTextCommandSetBlipName(blip)

        CreateThread(function()
            Wait(10000)
            if DoesBlipExist(blip) then SetBlipFlashes(blip, false) end
        end)

        return blip
    end

    local function StartCrateBeacon(ctx, options)
        ctx.markerActive = true
        local markerHeight = options.markerHeight or 1.45
        local markerScale = options.markerScale or vector3(0.4, 0.4, 0.4)
        local drawDistance = options.markerDrawDistance or 120.0
        local color = options.markerColor or { r = 255, g = 120, b = 64, a = 180 }

        CreateThread(function()
            while ctx.markerActive and ctx.prop and DoesEntityExist(ctx.prop) do
                local playerPed = PlayerPedId()
                if playerPed ~= 0 and DoesEntityExist(playerPed) then
                    local playerCoords = GetEntityCoords(playerPed)
                    local propCoords = GetEntityCoords(ctx.prop)
                    local distance = #(playerCoords - propCoords)
                    if distance <= drawDistance then
                        DrawMarker(28, propCoords.x, propCoords.y, propCoords.z + markerHeight,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            markerScale.x, markerScale.y, markerScale.z,
                            color.r, color.g, color.b, color.a,
                            false, false, 2, false, nil, nil, false)
                        DrawLightWithRange(propCoords.x, propCoords.y, propCoords.z + 1.1, 255, 96, 64, 8.0, 2.0)
                        Wait(0)
                    else
                        Wait(300)
                    end
                else
                    Wait(500)
                end
            end
        end)
    end

    function CXEC_GetSharedRewardCrateContext(crateId)
        return SharedRewardCrates[tostring(crateId or '')]
    end

    function CXEC_RequestSharedRewardCrate(crateId)
        crateId = tostring(crateId or '')
        if crateId == '' then return nil end

        local existing = SharedRewardCrates[crateId]
        if existing and existing.prop and DoesEntityExist(existing.prop) then
            return existing
        end

        TriggerServerEvent('corex-events:server:requestSharedRewardCrate', crateId)
        return nil
    end

    function CXEC_ClearSharedRewardCrate(crateId)
        crateId = tostring(crateId or '')
        if crateId == '' then return end

        local ctx = SharedRewardCrates[crateId]
        if ctx then
            CXEC_CleanupRewardCrate(ctx)
            SharedRewardCrates[crateId] = nil
        end
    end

    function CXEC_SpawnRewardCrate(options)
        options = options or {}
        local coords = options.coords
        if coords then
            coords = vector3(coords.x or coords[1] or 0.0, coords.y or coords[2] or 0.0, coords.z or coords[3] or 0.0)
            options.coords = coords
        end
        if options.center then
            options.center = vector3(options.center.x or options.center[1] or 0.0, options.center.y or options.center[2] or 0.0, options.center.z or options.center[3] or 0.0)
        end
        if options.markerScale then
            options.markerScale = vector3(options.markerScale.x or options.markerScale[1] or 0.0, options.markerScale.y or options.markerScale[2] or 0.0, options.markerScale.z or options.markerScale[3] or 0.0)
        end
        if not coords then
            ReportCrateIssue(options.eventId, 'crate_spawn', 'missing coords')
            return nil
        end

        local prop, modelHash, placedCoords, usedModel = nil, nil, nil, nil
        local existingNetId = tonumber(options.existingNetId or options.netId)

        if existingNetId and existingNetId > 0 then
            prop = TryResolveSharedCrateEntity(existingNetId, options.entityTimeoutMs)
            if not prop or not DoesEntityExist(prop) then
                ReportCrateIssue(options.eventId, 'crate_net_entity_missing', ('netId=%s'):format(tostring(existingNetId)))
                return nil
            end

            modelHash = GetEntityModel(prop)
            placedCoords = GetEntityCoords(prop)
            usedModel = options.model
        else
            RequestGroundCollision(vector3(coords.x, coords.y, coords.z), 8)
            local groundZ, foundGround = ResolveGroundZ(coords.x, coords.y, coords.z + 20.0)
            if not foundGround then
                groundZ, foundGround = ResolveGroundZ(coords.x, coords.y, 1000.0)
            end
            if not foundGround then
                groundZ = coords.z
            end

            local spawnBase = vector3(coords.x, coords.y, groundZ + 0.5)
            local fallbackModels = options.fallbackModels or { 'prop_mil_crate_01', 'prop_mil_crate_02', 'prop_box_ammo04a', 'prop_box_ammo02a' }
            local candidateModels = {}
            local seenModels = {}

            local function pushModel(model)
                if not model or seenModels[model] then return end
                seenModels[model] = true
                candidateModels[#candidateModels + 1] = model
            end

            pushModel(options.model)
            for _, model in ipairs(fallbackModels) do
                pushModel(model)
            end

            EventPrint(('spawn request event=%s model=%s x=%.2f y=%.2f z=%.2f foundGround=%s'):format(
                tostring(options.eventId or 'unknown'),
                tostring(options.model),
                spawnBase.x, spawnBase.y, spawnBase.z,
                tostring(foundGround)
            ))

            for _, candidateModel in ipairs(candidateModels) do
                for attempt = 1, 2 do
                    RequestGroundCollision(spawnBase, attempt == 1 and 5 or 8)
                    local attemptCoords = vector3(spawnBase.x, spawnBase.y, spawnBase.z + ((attempt - 1) * 0.35))
                    prop, modelHash = SpawnLocalRewardObject(candidateModel, attemptCoords, options.eventId, options.networked)

                    if prop and DoesEntityExist(prop) then
                        local snapped, finalCoords, finalGap = SnapCrateToGround(prop, modelHash, attemptCoords)
                        if snapped then
                            usedModel = candidateModel
                            placedCoords = finalCoords
                            EventPrint(('spawn success event=%s model=%s attempt=%d entity=%s x=%.2f y=%.2f z=%.2f gap=%.3f'):format(
                                tostring(options.eventId or 'unknown'),
                                tostring(candidateModel),
                                attempt,
                                tostring(prop),
                                finalCoords.x, finalCoords.y, finalCoords.z,
                                finalGap or -1.0
                            ))
                            break
                        end

                        ReportCrateIssue(options.eventId, 'crate_ground_snap_retry', ('attempt=%d model=%s x=%.2f y=%.2f z=%.2f'):format(
                            attempt, tostring(candidateModel), attemptCoords.x, attemptCoords.y, attemptCoords.z
                        ))
                        DeleteEntity(prop)
                        prop = nil
                    else
                        ReportCrateIssue(options.eventId, 'crate_spawn_attempt', ('attempt=%d model=%s x=%.2f y=%.2f z=%.2f'):format(
                            attempt, tostring(candidateModel), attemptCoords.x, attemptCoords.y, attemptCoords.z
                        ))
                    end
                end

                if prop and DoesEntityExist(prop) and placedCoords then
                    break
                end
            end

            if not prop or not DoesEntityExist(prop) or not placedCoords then
                ReportCrateIssue(options.eventId, 'crate_spawn_failed', ('model=%s x=%.2f y=%.2f z=%.2f foundGround=%s'):format(
                    tostring(options.model), spawnBase.x, spawnBase.y, spawnBase.z, tostring(foundGround)
                ))
                return nil
            end

            SetEntityHeading(prop, options.heading or 0.0)
            SetEntityVisible(prop, true, false)
            ResetEntityAlpha(prop)
            SetEntityCollision(prop, true, true)
            FreezeEntityPosition(prop, true)
        end

        SetEntityVisible(prop, true, false)
        ResetEntityAlpha(prop)
        SetEntityCollision(prop, true, true)

        local target = options.target or {}
        if target.event then
            local ok, err = pcall(function()
                exports['corex-core']:AddTarget(prop, {
                    text = target.text or 'Open Crate',
                    icon = target.icon or 'fa-box-open',
                    distance = target.distance or 2.5,
                    event = target.event,
                    data = target.data or {},
                })
            end)
            if not ok then
                ReportCrateIssue(options.eventId, 'crate_target_failed', err)
            end
        end

        local ctx = {
            prop = prop,
            blip = nil,
            ptfx = nil,
            markerActive = false,
            eventId = options.eventId,
            coords = placedCoords,
            model = usedModel or options.model,
            isShared = existingNetId and existingNetId > 0 or options.networked == true,
            sharedNetId = existingNetId or 0,
        }

        if options.flare ~= false then
            ctx.ptfx = StartCrateFlare(placedCoords)
            if not ctx.ptfx then
                ReportCrateIssue(options.eventId, 'crate_flare_failed', ('model=%s x=%.2f y=%.2f z=%.2f'):format(
                    tostring(options.model), placedCoords.x, placedCoords.y, placedCoords.z
                ))
            end
        end

        if options.marker ~= false then
            StartCrateBeacon(ctx, options)
        end

        local function ensureBlip()
            if ctx.blip or not ctx.prop or not DoesEntityExist(ctx.prop) then return end
            local propCoords = GetEntityCoords(ctx.prop)
            ctx.blip = CreateCrateBlip(propCoords, options.blipLabel, options.blipColor, options.blipSprite, options.blipScale)
        end

        if options.revealRadius and options.center then
            CreateThread(function()
                while ctx.prop and DoesEntityExist(ctx.prop) and not ctx.blip do
                    local playerPed = PlayerPedId()
                    if playerPed ~= 0 and DoesEntityExist(playerPed) then
                        local playerCoords = GetEntityCoords(playerPed)
                        if #(playerCoords - options.center) <= options.revealRadius then
                            ensureBlip()
                            return
                        end
                    end
                    Wait(500)
                end
            end)
        elseif options.createBlipImmediately then
            ensureBlip()
        end

        return ctx
    end

    function CXEC_CleanupRewardCrate(ctx)
        if not ctx then return end
        ctx.markerActive = false

        if ctx.prop then
            pcall(function()
                exports['corex-core']:RemoveTarget(ctx.prop)
            end)
            if DoesEntityExist(ctx.prop) then
                if ctx.isShared then
                    TryDeleteSharedEntity(ctx.prop)
                else
                    DeleteEntity(ctx.prop)
                end
            end
            ctx.prop = nil
        end

        if ctx.blip and DoesBlipExist(ctx.blip) then
            RemoveBlip(ctx.blip)
            ctx.blip = nil
        end

        if ctx.ptfx then
            StopParticleFxLooped(ctx.ptfx, false)
            ctx.ptfx = nil
        end
    end

    RegisterNetEvent('corex-events:client:spawnSharedRewardCrateHost', function(crateId, options)
        crateId = tostring(crateId or '')
        if crateId == '' or not options then return end

        local existing = SharedRewardCrates[crateId]
        if existing and existing.prop and DoesEntityExist(existing.prop) then
            local sharedNetId = existing.sharedNetId
            if sharedNetId and sharedNetId ~= 0 then
                TriggerServerEvent('corex-events:server:sharedRewardCrateSpawned', crateId, {
                    netId = sharedNetId,
                    coords = { x = existing.coords.x, y = existing.coords.y, z = existing.coords.z },
                    model = existing.model,
                    heading = GetEntityHeading(existing.prop),
                })
            end
            return
        end

        options.eventId = crateId
        options.networked = true

        local ctx = CXEC_SpawnRewardCrate(options)
        if not ctx or not ctx.prop or not DoesEntityExist(ctx.prop) then
            ReportCrateIssue(crateId, 'shared_host_spawn_failed', 'failed to create shared reward crate')
            return
        end

        local netId = NetworkGetNetworkIdFromEntity(ctx.prop)
        if not netId or netId == 0 then
            ReportCrateIssue(crateId, 'shared_host_spawn_failed', 'missing network id')
            CXEC_CleanupRewardCrate(ctx)
            return
        end

        ctx.isShared = true
        ctx.sharedNetId = netId
        SharedRewardCrates[crateId] = ctx

        TriggerServerEvent('corex-events:server:sharedRewardCrateSpawned', crateId, {
            netId = netId,
            coords = { x = ctx.coords.x, y = ctx.coords.y, z = ctx.coords.z },
            model = ctx.model,
            heading = GetEntityHeading(ctx.prop),
        })
    end)

    RegisterNetEvent('corex-events:client:sharedRewardCrateReady', function(crateId, options)
        crateId = tostring(crateId or '')
        if crateId == '' or not options then return end

        local existing = SharedRewardCrates[crateId]
        if existing and existing.prop and DoesEntityExist(existing.prop) then
            return
        end

        options.eventId = crateId
        options.existingNetId = options.netId

        local ctx = CXEC_SpawnRewardCrate(options)
        if not ctx then
            return
        end

        ctx.isShared = true
        ctx.sharedNetId = tonumber(options.netId) or 0
        SharedRewardCrates[crateId] = ctx
    end)
end

-- Event routing ────────────────────────────────────────────────
RegisterNetEvent('corex-events:client:syncSnapshot', function(snapshot)
    for _, state in ipairs(snapshot or {}) do
        ActiveEventsC[state.id] = state
        local h = ClientHandlers[state.type]
        if h and h.start then
            local ok, err = pcall(h.start, state, { fromSync = true })
            if not ok then Debug('Error', 'sync start failed: ' .. tostring(err)) end
        end
        CXEC_UI_AddEvent(state)
    end
end)

RegisterNetEvent('corex-events:client:eventStart', function(state)
    ActiveEventsC[state.id] = state
    local h = ClientHandlers[state.type]
    if h and h.start then
        local ok, err = pcall(h.start, state)
        if not ok then Debug('Error', 'start failed: ' .. tostring(err)) end
    end
    CXEC_UI_AddEvent(state)
end)

RegisterNetEvent('corex-events:client:eventUpdate', function(eventId, patch)
    local state = ActiveEventsC[eventId]
    if not state then return end
    for k, v in pairs(patch or {}) do state[k] = v end

    local h = ClientHandlers[state.type]
    if h and h.update then
        local ok, err = pcall(h.update, state, patch)
        if not ok then Debug('Error', 'update failed: ' .. tostring(err)) end
    end
    CXEC_UI_UpdateEvent(eventId, patch)
end)

RegisterNetEvent('corex-events:client:eventEnd', function(eventId, reason)
    local state = ActiveEventsC[eventId]
    if not state then return end

    local h = ClientHandlers[state.type]
    if h and h.stop then
        local ok, err = pcall(h.stop, state, reason)
        if not ok then Debug('Error', 'stop failed: ' .. tostring(err)) end
    end

    ActiveEventsC[eventId] = nil
    CXEC_UI_RemoveEvent(eventId, reason)
end)

-- Boot ─────────────────────────────────────────────────────────
CreateThread(function()
    InitCorex()

    -- Wait for player to be fully spawned, then request sync
    while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
    Wait(2000)  -- small grace period for other resources

    TriggerServerEvent('corex-events:server:requestSync')
    TriggerServerEvent('corex-events:server:requestSharedRewardCrateSync')
    Debug('Info', 'Sync requested')
end)

CreateThread(function()
    while true do
        while not NetworkIsPlayerActive(PlayerId()) do Wait(1000) end
        TriggerServerEvent('corex-events:server:requestSharedRewardCrateSync')
        Wait(10000)
    end
end)

-- Teleport helper (admin command support) ─────────────────────
RegisterNetEvent('corex-events:client:teleport', function(loc)
    if not loc or not loc.x then return end
    local Corex = exports['corex-core']:GetCoreObject()
    local ped = (Corex and Corex.Functions and Corex.Functions.GetPed) and Corex.Functions.GetPed() or 0
    if not ped or ped == 0 then return end
    -- Request terrain around destination so we don't fall through the map
    RequestCollisionAtCoord(loc.x, loc.y, loc.z)
    local t = GetGameTimer()
    while not HasCollisionLoadedAroundEntity(ped) and (GetGameTimer() - t) < 2500 do
        Wait(50)
    end
    SetEntityCoords(ped, loc.x, loc.y, loc.z + 0.5, false, false, false, false)
end)

-- Resource stop cleanup ────────────────────────────────────────
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for crateId, ctx in pairs(SharedRewardCrates) do
        CXEC_CleanupRewardCrate(ctx)
        SharedRewardCrates[crateId] = nil
    end
    for id, state in pairs(ActiveEventsC) do
        local h = ClientHandlers[state.type]
        if h and h.stop then pcall(h.stop, state, 'resource_stop') end
    end
    ActiveEventsC = {}
end)
