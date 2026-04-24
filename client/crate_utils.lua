if CXEC_SpawnRewardCrate then
    return
end

local function LoadNamedPtfx(asset, timeoutMs)
    if HasNamedPtfxAssetLoaded(asset) then
        return true
    end

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
    if not hash or not IsModelInCdimage(hash) then
        return nil
    end

    if HasModelLoaded(hash) then
        return hash
    end

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
    local probeHeights = {
        base + 25.0,
        base + 50.0,
        base + 100.0,
        base + 250.0,
        1000.0,
    }

    for _, probe in ipairs(probeHeights) do
        local found, groundZ = GetGroundZFor_3dCoord(x, y, probe, false)
        if found then
            return groundZ, true
        end
    end

    return base, false
end

local function ResolveModelBaseOffset(model)
    local hash = LoadModelHash(model)
    if not hash then
        return 0.0
    end

    local minDim, maxDim = GetModelDimensions(hash)
    return math.max(0.0, -(minDim.z or 0.0))
end

local function RequestGroundCollision(coords, passes)
    local count = passes or 6
    for _ = 1, count do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(75)
    end
end

local function SnapCrateToGround(prop, model, targetCoords)
    if not prop or not DoesEntityExist(prop) then
        return false, nil
    end

    local groundZ, foundGround = ResolveGroundZ(targetCoords.x, targetCoords.y, targetCoords.z + 20.0)
    local baseOffset = ResolveModelBaseOffset(model)
    local snappedZ = (foundGround and groundZ or targetCoords.z) + baseOffset + 0.02

    FreezeEntityPosition(prop, false)
    SetEntityCollision(prop, true, true)
    SetEntityCoordsNoOffset(prop, targetCoords.x, targetCoords.y, snappedZ, false, false, false)
    PlaceObjectOnGroundProperly(prop)

    for _ = 1, 6 do
        Wait(50)
        RequestCollisionAtCoord(targetCoords.x, targetCoords.y, snappedZ)
        PlaceObjectOnGroundProperly(prop)
    end

    FreezeEntityPosition(prop, true)

    local finalCoords = GetEntityCoords(prop)
    return true, vector3(finalCoords.x, finalCoords.y, finalCoords.z)
end

local function ReportCrateIssue(eventId, stage, message)
    TriggerServerEvent('corex-events:server:clientCrateIssue', eventId or 'unknown', stage or 'unknown', tostring(message or 'unknown'))
end
CXEC_ReportCrateIssue = ReportCrateIssue

local function StartCrateFlare(coords)
    local effectSets = {
        { asset = 'scr_rcbarry2', effect = 'scr_clown_appears', scale = 1.8 },
        { asset = 'core', effect = 'exp_grd_flare', scale = 1.15 },
    }

    for _, entry in ipairs(effectSets) do
        if LoadNamedPtfx(entry.asset) then
            UseParticleFxAssetNextCall(entry.asset)
            local handle = StartParticleFxLoopedAtCoord(
                entry.effect,
                coords.x,
                coords.y,
                coords.z + 0.35,
                0.0,
                0.0,
                0.0,
                entry.scale,
                false,
                false,
                false,
                false
            )

            if handle and handle ~= 0 then
                return handle
            end
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
        if DoesBlipExist(blip) then
            SetBlipFlashes(blip, false)
        end
    end)

    return blip
end

local function StartCrateBeacon(ctx, options)
    local markerHeight = options.markerHeight or 1.55
    local markerScale = options.markerScale or vector3(0.35, 0.35, 0.35)
    local drawDistance = options.markerDrawDistance or 120.0
    local color = options.markerColor or { r = 255, g = 95, b = 64, a = 190 }

    ctx.markerThread = CreateThread(function()
        while ctx.prop and DoesEntityExist(ctx.prop) do
            local playerPed = PlayerPedId()
            if playerPed and playerPed ~= 0 and DoesEntityExist(playerPed) then
                local playerCoords = GetEntityCoords(playerPed)
                local propCoords = GetEntityCoords(ctx.prop)
                local distance = #(playerCoords - propCoords)

                if distance <= drawDistance then
                    DrawMarker(
                        28,
                        propCoords.x,
                        propCoords.y,
                        propCoords.z + markerHeight,
                        0.0,
                        0.0,
                        0.0,
                        0.0,
                        0.0,
                        0.0,
                        markerScale.x,
                        markerScale.y,
                        markerScale.z,
                        color.r,
                        color.g,
                        color.b,
                        color.a,
                        false,
                        false,
                        2,
                        false,
                        nil,
                        nil,
                        false
                    )
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

function CXEC_SpawnRewardCrate(options)
    options = options or {}

    local Corex = CXEC_GetCorex and CXEC_GetCorex()
    if not Corex or not Corex.Functions then
        ReportCrateIssue(options.eventId, 'crate_spawn', 'core unavailable')
        return nil
    end

    local coords = options.coords
    if not coords then
        ReportCrateIssue(options.eventId, 'crate_spawn', 'missing coords')
        return nil
    end

    local groundZ, foundGround = ResolveGroundZ(coords.x, coords.y, coords.z + 20.0)
    local spawnBase = vector3(coords.x, coords.y, groundZ + 0.5)
    local spawnOpts = {
        placeOnGround = false,
        networked = false,
        freeze = false,
    }

    local prop = nil
    local placedCoords = nil

    for attempt = 1, 2 do
        RequestGroundCollision(spawnBase, attempt == 1 and 5 or 8)

        local attemptCoords = vector3(spawnBase.x, spawnBase.y, spawnBase.z + ((attempt - 1) * 0.35))
        prop = Corex.Functions.SpawnProp(options.model, attemptCoords, spawnOpts)

        if prop and DoesEntityExist(prop) then
            local snapped, finalCoords = SnapCrateToGround(prop, options.model, attemptCoords)
            if snapped then
                placedCoords = finalCoords
                break
            end

            ReportCrateIssue(options.eventId, 'crate_ground_snap_retry', ('attempt=%d model=%s x=%.2f y=%.2f z=%.2f foundGround=%s'):format(
                attempt,
                tostring(options.model),
                attemptCoords.x,
                attemptCoords.y,
                attemptCoords.z,
                tostring(foundGround)
            ))

            DeleteEntity(prop)
            prop = nil
        else
            ReportCrateIssue(options.eventId, 'crate_spawn_attempt', ('attempt=%d model=%s x=%.2f y=%.2f z=%.2f'):format(
                attempt,
                tostring(options.model),
                attemptCoords.x,
                attemptCoords.y,
                attemptCoords.z
            ))
        end
    end

    if not prop or not DoesEntityExist(prop) or not placedCoords then
        ReportCrateIssue(options.eventId, 'crate_spawn_failed', ('model=%s x=%.2f y=%.2f z=%.2f foundGround=%s'):format(
            tostring(options.model),
            spawnBase.x,
            spawnBase.y,
            spawnBase.z,
            tostring(foundGround)
        ))
        return nil
    end

    SetEntityHeading(prop, options.heading or 0.0)
    FreezeEntityPosition(prop, true)

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
        markerThread = nil,
        eventId = options.eventId,
        coords = placedCoords,
    }

    if options.flare ~= false then
        ctx.ptfx = StartCrateFlare(placedCoords)
    end

    if options.marker ~= false then
        StartCrateBeacon(ctx, options)
    end

    local function ensureBlip()
        if ctx.blip or not ctx.prop or not DoesEntityExist(ctx.prop) then
            return
        end

        local propCoords = GetEntityCoords(ctx.prop)
        ctx.blip = CreateCrateBlip(
            propCoords,
            options.blipLabel,
            options.blipColor,
            options.blipSprite,
            options.blipScale
        )
    end

    if options.revealRadius and options.center then
        CreateThread(function()
            while ctx.prop and DoesEntityExist(ctx.prop) and not ctx.blip do
                local playerPed = PlayerPedId()
                if playerPed and playerPed ~= 0 and DoesEntityExist(playerPed) then
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
    if not ctx then
        return
    end

    if ctx.prop then
        pcall(function()
            exports['corex-core']:RemoveTarget(ctx.prop)
        end)
        if DoesEntityExist(ctx.prop) then
            DeleteEntity(ctx.prop)
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

    ctx.markerThread = nil
end
