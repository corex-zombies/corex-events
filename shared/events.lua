CorexEvents = CorexEvents or {}
CorexEvents.Catalog = {

    supply_drop = {
        type        = 'supply_drop',
        label       = 'Supply Drop',
        description = 'A military transport is dropping supplies. Secure the crate.',
        icon        = 'helicopter',
        severity    = 'info',

        weight      = 30,
        cooldown    = 900,
        duration    = 600,
        minPlayers  = 1,
        announceLead = 60,
    },

    zombie_outbreak = {
        type        = 'zombie_outbreak',
        label       = 'Zombie Outbreak',
        description = 'Infected concentration reported. Clear the zone or evacuate.',
        icon        = 'zombie_outbreak',
        severity    = 'danger',

        weight      = 50,
        cooldown    = 600,
        duration    = 420,
        minPlayers  = 1,
        announceLead = 30,
    },

    convoy_ambush = {
        type        = 'convoy_ambush',
        label       = 'Convoy Ambush',
        description = 'A military convoy was ambushed by the infected. Salvage what you can.',
        icon        = 'truck',
        severity    = 'danger',

        weight      = 35,
        cooldown    = 720,
        duration    = 480,
        minPlayers  = 1,
        announceLead = 45,
    },

    airdrop_crash = {
        type        = 'airdrop_crash',
        label       = 'Crash Site',
        description = 'A cargo plane went down. High-value loot scattered across the wreckage.',
        icon        = 'plane',
        severity    = 'warning',

        weight      = 30,
        cooldown    = 600,
        duration    = 540,
        minPlayers  = 1,
        announceLead = 30,
    },

    survivor_rescue = {
        type        = 'survivor_rescue',
        label       = 'Survivor SOS',
        description = 'Survivors trapped by zombies are calling for help. Rescue them for a reward.',
        icon        = 'person',
        severity    = 'warning',

        weight      = 40,
        cooldown    = 540,
        duration    = 360,
        minPlayers  = 1,
        announceLead = 20,
    },

    extraction = {
        type        = 'extraction',
        label       = 'Extraction Point',
        description = 'Hold the extraction zone until the helicopter arrives. Defend against waves.',
        icon        = 'helicopter',
        severity    = 'danger',

        weight      = 25,
        cooldown    = 900,
        duration    = 420,
        minPlayers  = 1,
        announceLead = 60,
    },

}

function CorexEvents.Get(eventType)
    local base = CorexEvents.Catalog[eventType]
    if not base then return nil end

    local merged = {}
    for k, v in pairs(base) do merged[k] = v end

    local override = Config and Config.EventDefaults and Config.EventDefaults[eventType]
    if override then
        for k, v in pairs(override) do merged[k] = v end
    end

    return merged
end

function CorexEvents.List()
    local list = {}
    for k, _ in pairs(CorexEvents.Catalog) do list[#list + 1] = k end
    return list
end
