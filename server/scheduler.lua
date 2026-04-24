-- ═══════════════════════════════════════════════════════════════
-- COREX Events · Scheduler
-- Owns the event loop. Picks eligible events via weighted random,
-- invokes handlers registered in main.lua, manages lifecycle.
-- ═══════════════════════════════════════════════════════════════

local serverBootTime = os.time()

-- Eligibility ─────────────────────────────────────────────────
local function IsTypeOnCooldown(eventType)
    local def = CorexEvents.Get(eventType)
    if not def then return true end
    local lastRun = LastRunByType[eventType] or 0
    return (os.time() - lastRun) < (def.cooldown or 600)
end

local function HasEnoughPlayers(eventType)
    local def = CorexEvents.Get(eventType)
    if not def then return false end
    return GetNumPlayerIndices() >= (def.minPlayers or 1)
end

local function ConcurrentLimitReached()
    local count = 0
    for _ in pairs(ActiveEvents) do count = count + 1 end
    local limit = Config.MaxConcurrentEvents or (Config.Scheduler and Config.Scheduler.maxConcurrentEvents) or 2
    limit = math.max(1, math.floor(tonumber(limit) or 2))
    return count >= limit
end

local function MinGapSatisfied()
    local latest = 0
    for _, state in pairs(ActiveEvents) do
        if state.startTime > latest then latest = state.startTime end
    end
    if latest == 0 then return true end
    return (os.time() - latest) >= (Config.Scheduler.minGapBetweenEvents or 300)
end

-- Weighted random picker ──────────────────────────────────────
local function PickEligibleEvent()
    local candidates = {}
    local totalWeight = 0

    for _, eventType in ipairs(CorexEvents.List()) do
        if not IsTypeOnCooldown(eventType)
           and HasEnoughPlayers(eventType)
           and EventHandlers[eventType] then
            local def = CorexEvents.Get(eventType)
            local w = def.weight or 10
            candidates[#candidates + 1] = { type = eventType, weight = w }
            totalWeight = totalWeight + w
        end
    end

    if totalWeight == 0 then return nil end

    local roll = math.random() * totalWeight
    local cum = 0
    for _, c in ipairs(candidates) do
        cum = cum + c.weight
        if roll <= cum then return c.type end
    end
    return candidates[1].type
end

-- Lifecycle ───────────────────────────────────────────────────

---Start a specific event by type.
---@param eventType string
---@param opts table|nil { forced = bool }
---@return boolean ok, string|nil err
function CXE_TriggerEvent(eventType, opts)
    opts = opts or {}

    local def = CorexEvents.Get(eventType)
    if not def then return false, 'unknown event type' end

    local handler = EventHandlers[eventType]
    if not handler or type(handler.start) ~= 'function' then
        return false, 'no handler registered'
    end

    if not opts.forced then
        if IsTypeOnCooldown(eventType) then return false, 'on cooldown' end
        if ConcurrentLimitReached()   then return false, 'concurrent limit' end
    else
        if ConcurrentLimitReached() then return false, 'concurrent limit (forced)' end
    end

    -- Build runtime state
    local state = {
        id           = CXE_GenerateId(eventType),
        type         = eventType,
        label        = def.label,
        description  = def.description,
        icon         = def.icon,
        severity     = def.severity,
        duration     = def.duration,
        announceLead = def.announceLead or 0,
        startTime    = os.time(),
        announceAt   = os.time(),
        dropAt       = os.time() + (def.announceLead or 0),
        endAt        = os.time() + (def.duration or 600),
        public       = true,
        location     = nil,
        locationName = nil,
        ctx          = {},           -- freeform bucket handlers can use
        forced       = opts.forced or false,
    }

    ActiveEvents[state.id]    = state
    LastRunByType[eventType]  = os.time()

    local ok, err = pcall(handler.start, state)
    if not ok then
        ActiveEvents[state.id] = nil
        CXE_Debug('Error', 'handler.start failed for ' .. eventType .. ': ' .. tostring(err))
        return false, 'handler error'
    end

    CXE_BroadcastStart(state)
    CXE_Debug('Info', ('Started event %s (%s) at %s'):format(
        state.id, state.type, state.locationName or 'no-location'))

    return true, state.id
end

---End an active event by id.
---@param eventId string
---@param reason string|nil
function CXE_EndEvent(eventId, reason)
    local state = ActiveEvents[eventId]
    if not state then return end

    local handler = EventHandlers[state.type]
    if handler and type(handler.stop) == 'function' then
        local ok, err = pcall(handler.stop, state, reason)
        if not ok then
            CXE_Debug('Error', 'handler.stop failed for ' .. state.type .. ': ' .. tostring(err))
        end
    end

    ActiveEvents[eventId] = nil
    CXE_BroadcastEnd(eventId, reason or 'completed')
    CXE_Debug('Info', ('Ended event %s (%s) · reason=%s'):format(
        eventId, state.type, reason or 'completed'))
end

-- Fast tick loop · active events only (every 2s when events are live).
-- When no events are running, back off to 10s — the slow loop schedules
-- new events anyway, so nothing is missed.
CreateThread(function()
    while not Config.Scheduler.enabled do Wait(5000) end

    while true do
        local hasActive = false
        for id, state in pairs(ActiveEvents) do
            hasActive = true
            if os.time() >= state.endAt then
                CXE_EndEvent(id, 'expired')
            else
                local handler = EventHandlers[state.type]
                if handler and type(handler.tick) == 'function' then
                    local ok, err = pcall(handler.tick, state)
                    if not ok then
                        CXE_Debug('Error', 'handler.tick failed: ' .. tostring(err))
                    end
                end
            end
        end
        Wait(hasActive and 2000 or 10000)
    end
end)

-- Slow loop · scheduling new events (every checkInterval) ─────
CreateThread(function()
    while not Config.Scheduler.enabled do Wait(5000) end

    -- Startup delay before first auto-scheduled event
    Wait((Config.Scheduler.startupDelay or 60) * 1000)

    while true do
        if MinGapSatisfied() and not ConcurrentLimitReached() then
            local pick = PickEligibleEvent()
            if pick then
                CXE_TriggerEvent(pick)
            end
        end
        Wait((Config.Scheduler.checkInterval or 60) * 1000)
    end
end)

-- Cleanup on resource stop ────────────────────────────────────
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id, _ in pairs(ActiveEvents) do
        CXE_EndEvent(id, 'resource_stop')
    end
end)
