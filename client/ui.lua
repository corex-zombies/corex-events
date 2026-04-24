-- ═══════════════════════════════════════════════════════════════
-- COREX Events · NUI Controller
-- Owns the event-banner HUD: adds/updates/removes event cards.
-- ═══════════════════════════════════════════════════════════════

local nuiReady = false

local function SendNUI(action, data)
    SendNUIMessage({ action = action, data = data })
end

function CXEC_UI_AddEvent(state)
    SendNUI('addEvent', state)
end

function CXEC_UI_UpdateEvent(eventId, patch)
    SendNUI('updateEvent', { id = eventId, patch = patch })
end

function CXEC_UI_RemoveEvent(eventId, reason)
    SendNUI('removeEvent', { id = eventId, reason = reason })
end

-- Init NUI ─────────────────────────────────────────────────────
CreateThread(function()
    -- Give NUI a moment to boot
    Wait(1500)
    nuiReady = true
    SendNUI('init', {})
end)

-- Periodic tick to refresh countdowns / distance ───────────────
CreateThread(function()
    while true do
        -- No active events → sleep longer. Avoids PlayerPedId/GetEntityCoords
        -- and an empty NUI dispatch every second when nothing is happening.
        if not next(ActiveEventsC) then
            Wait(3000)
            goto continue
        end

        Wait(1000)
        if not nuiReady then goto continue end

        local Corex = exports['corex-core']:GetCoreObject()
        local coords = (Corex and Corex.Functions and Corex.Functions.GetCoords) and Corex.Functions.GetCoords() or nil
        local pos = coords and vector3(coords.x, coords.y, coords.z) or vector3(0, 0, 0)
        local updates = {}
        for id, state in pairs(ActiveEventsC) do
            local distance = nil
            if state.location then
                distance = #(pos - vector3(state.location.x, state.location.y, state.location.z))
            end
            updates[#updates + 1] = {
                id        = id,
                now       = GetGameTimer(),
                distance  = distance and math.floor(distance) or nil,
            }
        end
        if #updates > 0 then
            SendNUI('tick', { events = updates, serverNow = nil })
        end
        ::continue::
    end
end)
