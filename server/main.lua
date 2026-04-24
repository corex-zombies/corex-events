-- ═══════════════════════════════════════════════════════════════
-- COREX Events · Server Main
-- Orchestrator. Owns the core reference, debug helpers,
-- handler registry, and exposes exports other resources can use.
-- ═══════════════════════════════════════════════════════════════

local Corex = nil
local lastSyncRequest = {}

ActiveEvents   = ActiveEvents   or {}
EventHandlers  = EventHandlers  or {}
LastRunByType  = LastRunByType  or {}
SharedRewardCrates = SharedRewardCrates or {}

-- Debug ────────────────────────────────────────────────────────
local function Debug(level, msg)
    if not Config.Debug and level ~= 'Error' then return end
    local tag = ({ Error = '^1', Warn = '^3', Info = '^2', Verbose = '^5' })[level] or '^7'
    print(tag .. '[COREX-EVENTS] ' .. tostring(msg) .. '^0')
end
CXE_Debug = Debug

-- Core acquisition ─────────────────────────────────────────────
local function InitCorex()
    local attempts = 0
    while not Corex and attempts < 30 do
        local ok, result = pcall(function()
            return exports['corex-core']:GetCoreObject()
        end)
        if ok and result then
            Corex = result
            Debug('Info', 'Core object acquired')
            return true
        end
        attempts = attempts + 1
        Wait(1000)
    end
    Debug('Error', 'Failed to acquire core object')
    return false
end
CXE_GetCorex = function() return Corex end

-- Handler registry ─────────────────────────────────────────────
-- Individual event files register themselves via this API.
--
-- handler = {
--     start = function(eventState) ... end,   -- runs when event begins
--     tick  = function(eventState) ... end,   -- runs every second (optional)
--     stop  = function(eventState) ... end,   -- runs on end/cancel
-- }
function CXE_RegisterHandler(eventType, handler)
    if not eventType or not handler or type(handler) ~= 'table' then
        Debug('Error', 'Invalid handler registration for ' .. tostring(eventType))
        return
    end
    EventHandlers[eventType] = handler
    Debug('Info', 'Registered handler: ' .. eventType)
end

-- ID generation ────────────────────────────────────────────────
local idCounter = 0
function CXE_GenerateId(eventType)
    idCounter = idCounter + 1
    return ('%s_%d_%d'):format(eventType, os.time(), idCounter)
end

-- Broadcast helpers ────────────────────────────────────────────
-- Normalize vector3 into plain table for reliable network serialization
local function SerializeLoc(loc)
    if not loc then return nil end
    return { x = loc.x, y = loc.y, z = loc.z }
end

local function ToVec3(loc)
    if not loc then return nil end
    return vector3(loc.x or loc[1] or 0.0, loc.y or loc[2] or 0.0, loc.z or loc[3] or 0.0)
end

local function SerializeVec3Maybe(vec)
    if not vec then return nil end
    return { x = vec.x, y = vec.y, z = vec.z }
end

local function CopyTable(value)
    if type(value) ~= 'table' then return value end

    local out = {}
    for k, v in pairs(value) do
        out[k] = CopyTable(v)
    end
    return out
end

local function IsSourceOnline(src)
    if not src or src <= 0 then return false end
    local ped = GetPlayerPed(src)
    return ped and ped ~= 0
end

local function DistSq(a, b)
    local dx = (a.x or 0.0) - (b.x or 0.0)
    local dy = (a.y or 0.0) - (b.y or 0.0)
    local dz = (a.z or 0.0) - (b.z or 0.0)
    return dx * dx + dy * dy + dz * dz
end

local function PickNearestRewardHost(coords, radius)
    if not coords then return nil end

    local bestSrc, bestDistSq = nil, math.huge
    local maxDistSq = (radius or 1200.0) ^ 2

    for _, srcStr in ipairs(GetPlayers()) do
        local src = tonumber(srcStr)
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local playerCoords = GetEntityCoords(ped)
            local distSq = DistSq(coords, playerCoords)
            if distSq <= maxDistSq and distSq < bestDistSq then
                bestSrc = src
                bestDistSq = distSq
            end
        end
    end

    return bestSrc
end

local function SerializeSharedRewardCrate(crate)
    if not crate then return nil end

    return {
        crateId = crate.id,
        eventId = crate.id,
        model = crate.model,
        coords = SerializeLoc(crate.coords),
        center = SerializeLoc(crate.center),
        heading = crate.heading or 0.0,
        flare = crate.flare,
        marker = crate.marker,
        blipLabel = crate.blipLabel,
        blipColor = crate.blipColor,
        blipSprite = crate.blipSprite,
        blipScale = crate.blipScale,
        revealRadius = crate.revealRadius,
        createBlipImmediately = crate.createBlipImmediately,
        markerHeight = crate.markerHeight,
        markerScale = SerializeVec3Maybe(crate.markerScale),
        markerDrawDistance = crate.markerDrawDistance,
        markerColor = CopyTable(crate.markerColor),
        target = CopyTable(crate.target),
        fallbackModels = CopyTable(crate.fallbackModels),
        syncRadius = crate.syncRadius,
        netId = crate.netId,
        hostSource = crate.hostSource,
    }
end

local function SendSharedRewardCrateReady(crate, target)
    if not crate or not crate.netId then return end
    TriggerClientEvent('corex-events:client:sharedRewardCrateReady', target, crate.id, SerializeSharedRewardCrate(crate))
end

local function TryAssignSharedRewardCrateHost(crateId, preferredSource)
    local crate = SharedRewardCrates[crateId]
    if not crate then return false, 'missing_crate' end
    if crate.netId then return true, crate.hostSource end

    local host = preferredSource
    if host and not IsSourceOnline(host) then
        host = nil
    end

    if not host then
        host = PickNearestRewardHost(crate.center or crate.coords, crate.syncRadius)
    end

    if not host then
        crate.hostSource = nil
        crate.hostAssignedAt = 0
        Debug('Verbose', ('Shared crate %s waiting for nearby host'):format(crateId))
        return false, 'no_host'
    end

    crate.hostSource = host
    crate.hostAssignedAt = GetGameTimer()
    TriggerClientEvent('corex-events:client:spawnSharedRewardCrateHost', host, crate.id, SerializeSharedRewardCrate(crate))
    Debug('Verbose', ('Shared crate %s assigned to host=%d'):format(crateId, host))
    return true, host
end

function CXE_RegisterSharedRewardCrate(crateId, options)
    crateId = tostring(crateId or '')
    if crateId == '' then
        return false, 'invalid_crate_id'
    end

    options = options or {}
    local coords = ToVec3(options.coords or options.location)
    if not coords then
        return false, 'missing_coords'
    end

    local crate = SharedRewardCrates[crateId] or {}
    crate.id = crateId
    crate.coords = coords
    crate.center = ToVec3(options.center) or coords
    crate.model = options.model or crate.model
    crate.heading = options.heading or crate.heading or 0.0
    crate.flare = options.flare
    crate.marker = options.marker
    crate.blipLabel = options.blipLabel
    crate.blipColor = options.blipColor
    crate.blipSprite = options.blipSprite
    crate.blipScale = options.blipScale
    crate.revealRadius = options.revealRadius
    crate.createBlipImmediately = options.createBlipImmediately
    crate.markerHeight = options.markerHeight
    crate.markerScale = ToVec3(options.markerScale) or crate.markerScale
    crate.markerDrawDistance = options.markerDrawDistance
    crate.markerColor = CopyTable(options.markerColor)
    crate.target = CopyTable(options.target)
    crate.fallbackModels = CopyTable(options.fallbackModels)
    crate.syncRadius = options.syncRadius or crate.syncRadius or 1200.0

    SharedRewardCrates[crateId] = crate

    if crate.netId then
        return true, crate.hostSource
    end

    return TryAssignSharedRewardCrateHost(crateId, options.hostSource)
end

function CXE_UnregisterSharedRewardCrate(crateId)
    SharedRewardCrates[tostring(crateId or '')] = nil
end

function CXE_BroadcastStart(eventState)
    local payload = {
        id          = eventState.id,
        type        = eventState.type,
        label       = eventState.label,
        description = eventState.description,
        icon        = eventState.icon,
        severity    = eventState.severity,
        location    = SerializeLoc(eventState.location),
        locationName= eventState.locationName,
        startTime   = eventState.startTime,
        duration    = eventState.duration,
        announceAt  = eventState.announceAt,
        dropAt      = eventState.dropAt,
        public      = eventState.public,
    }
    TriggerClientEvent('corex-events:client:eventStart', -1, payload)
    Debug('Info', ('Broadcast START · %s · type=%s · loc=%s'):format(
        eventState.id, eventState.type, eventState.locationName or '?'))
end

function CXE_BroadcastUpdate(eventState, patch)
    TriggerClientEvent('corex-events:client:eventUpdate', -1, eventState.id, patch or {})
end

function CXE_BroadcastEnd(eventId, reason)
    TriggerClientEvent('corex-events:client:eventEnd', -1, eventId, reason)
end

-- Player sync on join ──────────────────────────────────────────
-- New players need the list of currently running events.
RegisterNetEvent('corex-events:server:requestSync', function()
    local src = source
    local now = GetGameTimer()
    if lastSyncRequest[src] and (now - lastSyncRequest[src]) < 5000 then return end
    lastSyncRequest[src] = now
    local snapshot = {}
    for _, state in pairs(ActiveEvents) do
        if state.public then
            snapshot[#snapshot + 1] = {
                id          = state.id,
                type        = state.type,
                label       = state.label,
                description = state.description,
                icon        = state.icon,
                severity    = state.severity,
                location    = SerializeLoc(state.location),
                locationName= state.locationName,
                startTime   = state.startTime,
                duration    = state.duration,
                announceAt  = state.announceAt,
                dropAt      = state.dropAt,
                public      = state.public,
                dropped     = state.ctx and (state.ctx.dropped or state.ctx.spawned) or false,
                spawned     = state.ctx and state.ctx.spawned or false,
                ctx         = state.ctx and {
                    heading       = state.ctx.heading,
                    debris        = state.ctx.debris,
                    currentWave   = state.ctx.currentWave,
                    totalWaves    = state.ctx.totalWaves,
                    zombieCount   = state.ctx.zombieCount,
                    spread        = state.ctx.spread,
                } or {},
            }
        end
    end
    TriggerClientEvent('corex-events:client:syncSnapshot', src, snapshot)
    Debug('Verbose', ('Sync → src=%d · %d active events'):format(src, #snapshot))
end)

AddEventHandler('playerDropped', function()
    lastSyncRequest[source] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source

    for crateId, crate in pairs(SharedRewardCrates) do
        if crate.hostSource == src and not crate.netId then
            crate.hostSource = nil
            crate.hostAssignedAt = 0
            TryAssignSharedRewardCrateHost(crateId)
        end
    end
end)

RegisterNetEvent('corex-events:server:clientCrateIssue', function(eventId, stage, message)
    local src = source
    Debug('Error', ('Client crate issue · src=%d · event=%s · stage=%s · %s'):format(
        src,
        tostring(eventId or 'unknown'),
        tostring(stage or 'unknown'),
        tostring(message or 'unknown')
    ))
end)

-- Admin / dev commands ─────────────────────────────────────────
-- Console always allowed; in-game requires the "corex.events.admin"
-- ACE permission OR the server owner can run it during testing.
RegisterNetEvent('corex-events:server:requestSharedRewardCrate', function(crateId)
    local src = source
    local crate = SharedRewardCrates[tostring(crateId or '')]
    if not crate then return end

    if crate.netId then
        SendSharedRewardCrateReady(crate, src)
        return
    end

    local now = GetGameTimer()
    local hostOnline = IsSourceOnline(crate.hostSource)
    local hostTimedOut = crate.hostAssignedAt and crate.hostAssignedAt > 0 and (now - crate.hostAssignedAt) > 8000

    if not hostOnline or hostTimedOut then
        TryAssignSharedRewardCrateHost(crate.id, src)
    end
end)

RegisterNetEvent('corex-events:server:requestSharedRewardCrateSync', function()
    local src = source
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end

    local playerCoords = GetEntityCoords(ped)

    for crateId, crate in pairs(SharedRewardCrates) do
        local center = crate.center or crate.coords
        local syncRadius = crate.syncRadius or 1200.0
        if center and DistSq(center, playerCoords) <= (syncRadius * syncRadius) then
            if crate.netId then
                SendSharedRewardCrateReady(crate, src)
            else
                local now = GetGameTimer()
                local hostOnline = IsSourceOnline(crate.hostSource)
                local hostTimedOut = crate.hostAssignedAt and crate.hostAssignedAt > 0 and (now - crate.hostAssignedAt) > 8000
                if not hostOnline or hostTimedOut then
                    TryAssignSharedRewardCrateHost(crateId, src)
                end
            end
        end
    end
end)

RegisterNetEvent('corex-events:server:sharedRewardCrateSpawned', function(crateId, data)
    local src = source
    local crate = SharedRewardCrates[tostring(crateId or '')]
    if not crate or not data then return end

    if crate.hostSource and crate.hostSource ~= src and IsSourceOnline(crate.hostSource) then
        Debug('Warn', ('Ignoring shared crate spawn from unexpected host src=%d crate=%s expected=%s'):format(
            src,
            tostring(crateId),
            tostring(crate.hostSource)
        ))
        return
    end

    local netId = tonumber(data.netId)
    if not netId or netId <= 0 then
        Debug('Warn', ('Shared crate %s reported invalid netId from src=%d'):format(tostring(crateId), src))
        return
    end

    crate.netId = netId
    crate.hostSource = src
    crate.hostAssignedAt = GetGameTimer()
    crate.coords = ToVec3(data.coords) or crate.coords
    crate.model = data.model or crate.model
    crate.heading = data.heading or crate.heading

    exports['corex-core']:BroadcastNearby(
        crate.center or crate.coords,
        crate.syncRadius or 1200.0,
        'corex-events:client:sharedRewardCrateReady',
        crate.id,
        SerializeSharedRewardCrate(crate)
    )

    Debug('Info', ('Shared crate ready: %s host=%d netId=%d'):format(crate.id, src, netId))
end)

local function IsAllowed(src)
    if src == 0 then return true end  -- server console
    if IsPlayerAceAllowed(src, 'corex.admin') then return true end
    if IsPlayerAceAllowed(src, 'corex.events.admin') then return true end
    if IsPlayerAceAllowed(src, 'command') then return true end
    return false
end

local function Reply(src, msg, color)
    color = color or '^3'
    if src == 0 then
        print(color .. '[COREX-EVENTS] ' .. msg .. '^0')
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = { 200, 180, 100 },
            args = { 'COREX-EVENTS', msg },
        })
    end
end

-- /cxe_trigger <type>   — force-start an event
RegisterCommand('cxe_trigger', function(src, args)
    if not IsAllowed(src) then
        Reply(src, 'Permission denied. Need corex.events.admin.', '^1')
        return
    end
    local eventType = args[1]
    if not eventType then
        Reply(src, 'Usage: /cxe_trigger <event_type>  (supply_drop, zombie_outbreak, convoy_ambush, airdrop_crash, survivor_rescue, extraction)')
        return
    end
    if CXE_TriggerEvent then
        local ok, errOrId = CXE_TriggerEvent(eventType, { forced = true })
        if ok then
            local state = ActiveEvents[errOrId]
            local loc = state and state.locationName or 'unknown'
            Reply(src, ('Triggered: %s @ %s'):format(eventType, loc), '^2')
            Reply(src, 'id=' .. tostring(errOrId), '^2')
        else
            Reply(src, 'Failed: ' .. tostring(errOrId), '^1')
        end
    else
        Reply(src, 'Scheduler not ready', '^1')
    end
end, false)

-- /cxe_tp <event_id>   — teleport to an active event (for testing)
RegisterCommand('cxe_tp', function(src, args)
    if not IsAllowed(src) then return end
    if src == 0 then Reply(src, 'cxe_tp must be run from in-game', '^1') return end

    local id = args[1]
    local state = id and ActiveEvents[id]

    -- If no id given, pick the first active event with a location
    if not state then
        for _, s in pairs(ActiveEvents) do
            if s.location then state = s break end
        end
    end

    if not state or not state.location then
        Reply(src, 'No active event with a location', '^3')
        return
    end

    local loc = state.location
    TriggerClientEvent('corex-events:client:teleport', src, {
        x = loc.x, y = loc.y, z = loc.z,
    })
    Reply(src, ('Teleporting to %s'):format(state.locationName or '?'), '^2')
end, false)

-- /cxe_list — print active events
RegisterCommand('cxe_list', function(src)
    if not IsAllowed(src) then return end
    local count = 0
    for id, state in pairs(ActiveEvents) do
        count = count + 1
        Reply(src, ('[%d] %s · id=%s · started=%ds ago'):format(
            count, state.type, id, os.time() - state.startTime), '^2')
    end
    if count == 0 then Reply(src, 'No active events', '^3') end
end, false)

-- /cxe_stop <id>
RegisterCommand('cxe_stop', function(src, args)
    if not IsAllowed(src) then return end
    local id = args[1]
    if not id then Reply(src, 'Usage: /cxe_stop <event_id>') return end
    if CXE_EndEvent then
        CXE_EndEvent(id, 'admin_stop')
        Reply(src, 'Stopped ' .. id, '^2')
    end
end, false)

-- Exports for other resources ──────────────────────────────────
exports('GetActiveEvents', function()
    local out = {}
    for id, state in pairs(ActiveEvents) do
        out[id] = {
            id       = state.id,
            type     = state.type,
            startTime= state.startTime,
            duration = state.duration,
            location = state.location,
        }
    end
    return out
end)

exports('TriggerEvent', function(eventType, opts)
    if CXE_TriggerEvent then return CXE_TriggerEvent(eventType, opts) end
    return false, 'scheduler not ready'
end)

exports('RegisterSharedRewardCrate', function(...) return CXE_RegisterSharedRewardCrate(...) end)
exports('UnregisterSharedRewardCrate', function(...) return CXE_UnregisterSharedRewardCrate(...) end)

-- Boot ─────────────────────────────────────────────────────────
CreateThread(function()
    InitCorex()
    print('^2======================================================^7')
    print('^2  COREX-EVENTS v2.0.0 loaded · 6 event types^7')
    print('^2  Supply Drop · Zombie Outbreak · Convoy Ambush^7')
    print('^2  Crash Site · Survivor Rescue · Extraction Point^7')
    print('^2  Commands: cxe_trigger <type> · cxe_list · cxe_stop <id>^7')
    print('^2======================================================^7')
    Debug('Info', 'Events system online · catalog size = ' .. #CorexEvents.List())
end)
