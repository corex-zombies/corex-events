-- ═══════════════════════════════════════════════════════════════
-- Supply Drop · client handler
-- Cinematic sequence: helicopter flies in, hovers, releases a
-- parachute-attached crate, leaves, crate lands with smoke flare.
--
-- Sync strategy: every client plays an identical, deterministic
-- sequence anchored to state.dropAt (os.time epoch, server-sent).
-- No per-frame network traffic; crate/heli/parachute are local
-- visual-only entities. The interactive crate is spawned locally
-- after landing and its AddTarget call ties into corex-loot via
-- the shared eventId (containerId).
-- ═══════════════════════════════════════════════════════════════

local State = {}  -- eventId → cinematic context

local function SearchSupplyCrate(entity, data)
    TriggerServerEvent('corex-loot:server:requestContainer', data.eventId)
end

RegisterNetEvent('corex-events:client:supplyDrop_searchCrate', function(entity, data)
    SearchSupplyCrate(entity, data)
end)

-- ─────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────

local function ToVec3(loc)
    if not loc then return nil end
    return vector3(loc.x or loc[1] or 0.0, loc.y or loc[2] or 0.0, loc.z or loc[3] or 0.0)
end

-- TODO: Move to Corex.Functions.LoadModel once implemented in corex-core
local function LoadModel(model, timeoutMs)
    local hash = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelInCdimage(hash) then
        CXEC_Debug('Warn', 'Model not in cdimage: ' .. tostring(model))
        return nil
    end
    RequestModel(hash)
    local t = GetGameTimer()
    while not HasModelLoaded(hash) do
        Wait(10)
        if GetGameTimer() - t > (timeoutMs or 5000) then
            CXEC_Debug('Warn', 'Model timeout: ' .. tostring(model))
            return nil
        end
    end
    return hash
end

-- TODO: Move to Corex.Functions.LoadPtfxAsset once implemented in corex-core
local function LoadPtfx(asset, timeoutMs)
    if HasNamedPtfxAssetLoaded(asset) then return true end
    RequestNamedPtfxAsset(asset)
    local t = GetGameTimer()
    while not HasNamedPtfxAssetLoaded(asset) do
        Wait(10)
        if GetGameTimer() - t > (timeoutMs or 3000) then return false end
    end
    return true
end

local function GroundZ(x, y, zGuess)
    local ok, z = GetGroundZFor_3dCoord(x, y, zGuess or 500.0, false)
    if ok then return z end
    return zGuess or 30.0
end

local function MakeBlip(coords, label, color)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 478)
    SetBlipColour(blip, color or 2)
    SetBlipScale(blip, 1.0)
    SetBlipAsShortRange(blip, false)
    SetBlipCategory(blip, 10)
    SetBlipDisplay(blip, 6)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Supply Drop')
    EndTextCommandSetBlipName(blip)
    return blip
end

-- Deterministic "random" direction derived from eventId so every
-- client picks the SAME heli approach vector without network sync.
local function HashVector(eventId)
    local sum = 0
    for i = 1, #eventId do sum = (sum * 31 + string.byte(eventId, i)) % 360 end
    local rad = math.rad(sum)
    return math.cos(rad), math.sin(rad)
end

-- ─────────────────────────────────────────────────────────────
-- Entity factories
-- ─────────────────────────────────────────────────────────────

-- TODO: Move to Corex.Functions.SpawnLocalVehicle once implemented in corex-core
local function SpawnHelicopter(model, x, y, z, heading)
    local hash = LoadModel(model)
    if not hash then return nil, nil end

    local veh = CreateVehicle(hash, x, y, z, heading, false, false)
    if not DoesEntityExist(veh) then
        SetModelAsNoLongerNeeded(hash)
        return nil, nil
    end
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineOn(veh, true, true, false)
    SetHeliBladesFullSpeed(veh)
    SetVehicleEngineHealth(veh, 1000.0)
    SetEntityInvincible(veh, true)
    SetVehicleDoorsLocked(veh, 4)

    local pilotHash = LoadModel('s_m_m_pilot_01')
    local ped
    if pilotHash then
        ped = CreatePedInsideVehicle(veh, 26, pilotHash, -1, false, false)
        if DoesEntityExist(ped) then
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanBeDraggedOut(ped, false)
            SetPedKeepTask(ped, true)
        end
        SetModelAsNoLongerNeeded(pilotHash)
    end

    SetModelAsNoLongerNeeded(hash)
    return veh, ped
end

-- TODO: Move to Corex.Functions.SpawnLocalObject once implemented in corex-core
local function SpawnObject(model, x, y, z, isDynamic)
    local hash = LoadModel(model)
    if not hash then return nil end
    local obj = CreateObject(hash, x, y, z, false, false, isDynamic and true or false)
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(obj) then return nil end
    return obj
end

-- ─────────────────────────────────────────────────────────────
-- Cinematic stages
-- ─────────────────────────────────────────────────────────────

local function StartSmoke(coords)
    local asset = 'scr_rcbarry2'
    if not LoadPtfx(asset) then
        -- Fallback to a more common asset if the primary fails
        asset = 'core'
        if not LoadPtfx(asset) then return nil end
        UseParticleFxAssetNextCall(asset)
        return StartParticleFxLoopedAtCoord(
            'exp_grd_flare',
            coords.x, coords.y, coords.z + 0.4,
            0.0, 0.0, 0.0,
            2.0, false, false, false, false
        )
    end
    UseParticleFxAssetNextCall(asset)
    return StartParticleFxLoopedAtCoord(
        'scr_clown_appears',
        coords.x, coords.y, coords.z + 0.4,
        0.0, 0.0, 0.0,
        2.2, false, false, false, false
    )
end

local function AttachTarget(eventId, prop)
    local ok, err = pcall(function()
        exports['corex-core']:AddTarget(prop, {
            text     = 'Search Supply Crate',
            icon     = 'fa-box-open',
            distance = 2.2,
            event    = 'corex-events:client:supplyDrop_searchCrate',
            data     = { eventId = eventId },
        })
    end)
    if not ok then
        CXEC_Debug('Error', 'AddTarget failed for supply crate: ' .. tostring(err))
    end
end

local function DetachTarget(prop)
    if not prop then return end
    pcall(function() exports['corex-core']:RemoveTarget(prop) end)
end

local function SpawnDirectLandedCrate(s, state, groundZ)
    local model = Config.SupplyDrop.crateModel or 'prop_mil_crate_01'
    local prop = SpawnObject(model, s.coords.x, s.coords.y, groundZ + 0.65, false)
    if not prop or not DoesEntityExist(prop) then
        CXEC_Debug('Error', 'Direct supply crate spawn failed for ' .. tostring(state.id))
        return nil
    end

    SetEntityAsMissionEntity(prop, true, true)
    SetEntityHeading(prop, Config.SupplyDrop.crateHeading or 0.0)
    SetEntityVisible(prop, true, false)
    ResetEntityAlpha(prop)
    SetEntityCollision(prop, true, true)
    FreezeEntityPosition(prop, false)

    for _ = 1, 10 do
        RequestCollisionAtCoord(s.coords.x, s.coords.y, groundZ)
        SetEntityCoordsNoOffset(prop, s.coords.x, s.coords.y, groundZ + 0.65, false, false, false)
        PlaceObjectOnGroundProperly(prop)
        Wait(50)
    end

    FreezeEntityPosition(prop, true)
    AttachTarget(state.id, prop)
    return prop
end

-- Spawn the final landed crate + flare smoke, wire up interaction
local function SpawnLandedCrate(s, state)
    if s.landed and s.prop and DoesEntityExist(s.prop) then
        return
    end

    CreateThread(function()
        local deadline = GetGameTimer() + 10000

        while State[state.id] == s and GetGameTimer() < deadline do
            local ctx = CXEC_GetSharedRewardCrateContext(state.id)
            if ctx and ctx.prop and DoesEntityExist(ctx.prop) then
                local landedCoords = ctx.coords or GetEntityCoords(ctx.prop)
                s.prop = ctx.prop
                if not s.ptfx then
                    s.ptfx = StartSmoke(landedCoords)
                end
                s.landed = true

                if s.blip and DoesBlipExist(s.blip) then
                    SetBlipFlashes(s.blip, false)
                    SetBlipColour(s.blip, 2)
                end
                return
            end

            CXEC_RequestSharedRewardCrate(state.id)
            Wait(250)
        end

        CXEC_Debug('Warn', 'Timed out waiting for shared landed crate: ' .. tostring(state.id))
    end)
end

-- Detach parachute, let it fall away, then fade and delete.
local function FadeOutParachute(parachute, fadeSec)
    if not parachute or not DoesEntityExist(parachute) then return end
    CreateThread(function()
        DetachEntity(parachute, true, true)
        SetEntityCollision(parachute, false, false)
        local dur = math.floor((fadeSec or 4.0) * 1000)
        NetworkFadeOutEntity(parachute, false, true)
        Wait(dur)
        if DoesEntityExist(parachute) then DeleteEntity(parachute) end
    end)
end

-- Slowly descend the attached crate using physics force
local function BeginParachuteDescent(s, state)
    local cfg = Config.SupplyDrop.cinematic
    CreateThread(function()
        local crate = s.airCrate
        if not crate or not DoesEntityExist(crate) then return end

        SetEntityDynamic(crate, true)
        ActivatePhysics(crate)

        while DoesEntityExist(crate) and not s.landed and State[state.id] do
            local cx, cy, cz = table.unpack(GetEntityCoords(crate))
            local gz = GroundZ(cx, cy, cz)
            if (cz - gz) <= 0.8 then
                -- Landed
                s.landed = true
                FadeOutParachute(s.parachute, cfg.parachuteFadeSec)
                s.parachute = nil
                if DoesEntityExist(crate) then DeleteEntity(crate) end
                s.airCrate = nil
                SpawnLandedCrate(s, state)
                return
            end
            -- Apply upward damping to simulate parachute drag (slow the fall)
            -- type 1 = force, applied at center of mass
            ApplyForceToEntity(crate, 1, 0.0, 0.0, (1.0 - (cfg.crateFallGravity or 0.18)) * 9.8 * 0.05,
                0.0, 0.0, 0.0, 0, false, true, true, false, true)
            Wait(50)
        end
    end)
end

-- Release the crate: detach from heli, attach parachute, descent thread
local function ReleaseCrate(s, state)
    local cfg = Config.SupplyDrop.cinematic
    local cx, cy, cz = s.coords.x, s.coords.y, s.coords.z

    -- Spawn crate in the air, attached to nothing initially
    local airZ = GroundZ(cx, cy, cz + 200.0) + (cfg.releaseHeightAGL or 80.0)
    local airCrate = SpawnObject(Config.SupplyDrop.crateModel, cx, cy, airZ, true)
    if not airCrate then
        -- Fallback: skip cinematic, drop directly
        CXEC_Debug('Warn', 'Air crate spawn failed, skipping to landed state')
        SpawnLandedCrate(s, state)
        return
    end
    SetEntityHeading(airCrate, Config.SupplyDrop.crateHeading or 0.0)
    s.airCrate = airCrate

    -- Parachute prop, attached above the crate
    local parachute = SpawnObject(cfg.parachuteModel, cx, cy, airZ + 2.0, false)
    if parachute then
        AttachEntityToEntity(parachute, airCrate, 0,
            0.0, 0.0, 2.2,       -- offset: above crate
            0.0, 0.0, 0.0,       -- rotation
            false, false, false, false, 2, true)
        s.parachute = parachute
    end

    BeginParachuteDescent(s, state)
end

-- Fly the helicopter toward the drop zone, hover, release, leave, despawn
local function RunHelicopterCinematic(s, state)
    local cfg = Config.SupplyDrop.cinematic
    local cx, cy, cz = s.coords.x, s.coords.y, s.coords.z

    -- Deterministic approach direction (same on every client)
    local dx, dy = HashVector(state.id)
    local spawnX = cx + dx * cfg.spawnDistance
    local spawnY = cy + dy * cfg.spawnDistance
    local spawnZ = cz + cfg.spawnAltitude
    local heliHeading = math.deg(math.atan(cy - spawnY, cx - spawnX)) - 90.0

    local veh, pilot = SpawnHelicopter(cfg.heliModel, spawnX, spawnY, spawnZ, heliHeading)
    if not veh then
        CXEC_Debug('Warn', 'Heli spawn failed, skipping cinematic → direct landing')
        SpawnLandedCrate(s, state)
        return
    end
    s.heli  = veh
    s.pilot = pilot

    -- Dispatch heli to hover above the drop zone
    -- TaskHeliMission: missionType 4 = goto, with alt band for hover
    if pilot and DoesEntityExist(pilot) then
        -- TODO: Corex.Functions.TaskHeliMission export
        TaskHeliMission(pilot, veh, 0, 0,
            cx, cy, cz + cfg.hoverAltitude,
            4,                       -- mission type: GOTO
            cfg.approachSpeed,       -- cruise speed
            cfg.approachRadius,      -- arrive radius
            heliHeading,
            cfg.hoverAltitude - 10,  -- minAlt
            cfg.hoverAltitude + 10,  -- maxAlt
            10.0                     -- flight zone radius
        )
    end

    -- Wait until the heli is within release radius, then release
    CreateThread(function()
        local releaseDeadline = GetGameTimer() + math.floor((cfg.approachSeconds + 20.0) * 1000)
        while DoesEntityExist(veh) and State[state.id] and GetGameTimer() < releaseDeadline do
            local hx, hy, _ = table.unpack(GetEntityCoords(veh))
            local dist2d = #(vector2(hx, hy) - vector2(cx, cy))
            if dist2d <= (cfg.approachRadius + 6.0) then
                break
            end
            Wait(200)
        end
        if not State[state.id] then return end

        ReleaseCrate(s, state)

        -- Leave: task heli to a far waypoint, then despawn
        if pilot and DoesEntityExist(pilot) and DoesEntityExist(veh) then
            local leaveX = cx + dx * cfg.leaveDistance
            local leaveY = cy + dy * cfg.leaveDistance
            local leaveZ = cz + cfg.spawnAltitude + 40.0
            TaskHeliMission(pilot, veh, 0, 0,
                leaveX, leaveY, leaveZ,
                4, cfg.approachSpeed * 1.2, 50.0, 0.0,
                cfg.spawnAltitude, cfg.spawnAltitude + 60.0, 10.0)
        end

        SetTimeout(math.floor((cfg.heliDespawnDelay or 25.0) * 1000), function()
            if s.heli and DoesEntityExist(s.heli) then
                SetEntityAsMissionEntity(s.heli, true, true)
                DeleteVehicle(s.heli)
                s.heli = nil
            end
            if s.pilot and DoesEntityExist(s.pilot) then
                DeleteEntity(s.pilot)
                s.pilot = nil
            end
        end)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Deterministic-start scheduler
-- Each client sleeps until (dropAt - approachSeconds) server-time,
-- then runs the same cinematic. If we're already past that, we
-- start immediately (joined mid-approach) or skip to landed.
-- ─────────────────────────────────────────────────────────────

local function ScheduleCinematic(s, state)
    local cfg = Config.SupplyDrop.cinematic
    -- state.dropAt is epoch seconds from server; GetCloudTimeAsInt() gives
    -- us the same on client (sandboxed Lua has no `os` library).
    local now = GetCloudTimeAsInt()
    local secondsUntilDrop = (state.dropAt or now) - now
    local secondsUntilStart = secondsUntilDrop - cfg.approachSeconds

    if secondsUntilStart <= 0 and secondsUntilDrop > 0 then
        -- Mid-approach: start immediately, crate will still release ~on time
        RunHelicopterCinematic(s, state)
        return
    end

    if secondsUntilStart > 0 then
        CreateThread(function()
            Wait(math.floor(secondsUntilStart * 1000))
            if not State[state.id] then return end  -- event may have ended
            if s.landed then return end              -- update() already fired
            RunHelicopterCinematic(s, state)
        end)
        return
    end

    -- Already past drop time and no landing broadcast yet: wait for update()
end

-- ─────────────────────────────────────────────────────────────
-- Handler
-- ─────────────────────────────────────────────────────────────

local handler = {}

function handler.start(state, meta)
    if State[state.id] then return end  -- idempotent

    local coords = ToVec3(state.location)
    if not coords then
        CXEC_Debug('Error', 'No location for ' .. (state.id or '?'))
        return
    end

    local s = {
        coords   = coords,
        landed   = false,
        prop     = nil,    -- final interactive crate
        airCrate = nil,    -- falling crate (deleted on landing)
        parachute= nil,
        heli     = nil,
        pilot    = nil,
        ptfx     = nil,
        blip     = MakeBlip(coords, state.label or 'Supply Drop', 2),
    }
    State[state.id] = s

    CXEC_Debug('Info', ('Supply drop announce · id=%s · %.1f, %.1f, %.1f'):format(
        state.id, coords.x, coords.y, coords.z))

    if state.dropped then
        -- Joined after crate already landed → skip to landed state
        SpawnLandedCrate(s, state)
    else
        if s.blip and DoesBlipExist(s.blip) then
            SetBlipFlashes(s.blip, true)
            SetBlipFlashInterval(s.blip, 500)
        end
        ScheduleCinematic(s, state)
    end
end

function handler.update(state, patch)
    local s = State[state.id]
    if not s then return end
    if not (patch and patch.dropped) then return end
    if s.landed then return end  -- idempotent: already handled

    -- Broadcast says crate has landed on the server (and corex-loot is
    -- registered). If our local cinematic is still running, let it finish
    -- naturally (the descent thread will call SpawnLandedCrate). If we
    -- somehow don't have an in-flight crate, spawn the landed crate now.
    if not s.airCrate and not s.landed then
        SpawnLandedCrate(s, state)
    end
end

function handler.stop(state, reason)
    local s = State[state.id]
    if not s then return end

    if s.prop then DetachTarget(s.prop) end
    if s.blip and DoesBlipExist(s.blip) then RemoveBlip(s.blip) end
    if CXEC_GetSharedRewardCrateContext(state.id) then
        CXEC_ClearSharedRewardCrate(state.id)
    elseif s.prop and DoesEntityExist(s.prop) then
        DeleteEntity(s.prop)
    end
    if s.airCrate and DoesEntityExist(s.airCrate) then DeleteEntity(s.airCrate) end
    if s.parachute and DoesEntityExist(s.parachute) then DeleteEntity(s.parachute) end
    if s.heli and DoesEntityExist(s.heli) then
        SetEntityAsMissionEntity(s.heli, true, true)
        DeleteVehicle(s.heli)
    end
    if s.pilot and DoesEntityExist(s.pilot) then DeleteEntity(s.pilot) end
    if s.ptfx then StopParticleFxLooped(s.ptfx, false) end

    State[state.id] = nil
    CXEC_Debug('Info', ('Supply drop cleaned up · %s · reason=%s'):format(state.id, reason or '?'))
end

-- Pickup feedback ─────────────────────────────────────────────
RegisterNetEvent('corex-events:client:pickupResult', function(ok, reason, item)
    if ok and item then
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(('+%d %s'):format(item.count, item.label or item.name))
        EndTextCommandThefeedPostTicker(false, false)
    elseif not ok then
        local msg = ({
            not_found  = 'Crate no longer available',
            not_landed = 'Drop still incoming',
            empty      = 'Crate is empty',
            inv_full   = 'Inventory full',
            inv_error  = 'Inventory error',
        })[reason] or 'Cannot pick up'
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName('~r~' .. msg)
        EndTextCommandThefeedPostTicker(false, false)
    end
end)

-- Resource-stop cleanup ───────────────────────────────────────
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id, s in pairs(State) do
        if s.prop then DetachTarget(s.prop) end
        if s.blip and DoesBlipExist(s.blip) then RemoveBlip(s.blip) end
        if CXEC_GetSharedRewardCrateContext(id) then
            CXEC_ClearSharedRewardCrate(id)
        elseif s.prop and DoesEntityExist(s.prop) then
            DeleteEntity(s.prop)
        end
        if s.airCrate and DoesEntityExist(s.airCrate) then DeleteEntity(s.airCrate) end
        if s.parachute and DoesEntityExist(s.parachute) then DeleteEntity(s.parachute) end
        if s.heli and DoesEntityExist(s.heli) then
            SetEntityAsMissionEntity(s.heli, true, true)
            DeleteVehicle(s.heli)
        end
        if s.pilot and DoesEntityExist(s.pilot) then DeleteEntity(s.pilot) end
        if s.ptfx then StopParticleFxLooped(s.ptfx, false) end
        State[id] = nil
    end
end)

-- Register with router ────────────────────────────────────────
CreateThread(function()
    while not CXEC_RegisterHandler do Wait(100) end
    CXEC_RegisterHandler('supply_drop', handler)
    CXEC_Debug('Info', 'supply_drop client handler registered (cinematic)')
end)
