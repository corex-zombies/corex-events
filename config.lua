Config = Config or {}

Config.Debug = false

Config.MaxConcurrentEvents = 2

Config.Scheduler = {
    enabled = true,
    checkInterval = 60,
    minGapBetweenEvents = 240,
    maxConcurrentEvents = Config.MaxConcurrentEvents,
    startupDelay = 60,
}

Config.EventDefaults = {
    supply_drop = {
        weight = 30,
        cooldown = 900,
        duration = 600,
        minPlayers = 1,
        announceLead = 60,
    },
    zombie_outbreak = {
        weight = 50,
        cooldown = 600,
        duration = 420,
        minPlayers = 1,
        announceLead = 30,
    },
    convoy_ambush = {
        weight = 35,
        cooldown = 720,
        duration = 480,
        minPlayers = 1,
        announceLead = 45,
    },
    airdrop_crash = {
        weight = 30,
        cooldown = 600,
        duration = 540,
        minPlayers = 1,
        announceLead = 30,
    },
    survivor_rescue = {
        weight = 40,
        cooldown = 540,
        duration = 360,
        minPlayers = 1,
        announceLead = 20,
    },
    extraction = {
        weight = 25,
        cooldown = 900,
        duration = 420,
        minPlayers = 1,
        announceLead = 60,
    },
}

Config.SupplyDrop = {
    dropZones = {
        { label = 'Sandy Shores Airfield', coords = vector3(1747.5, 3273.7, 41.1) },
        { label = 'Grapeseed Fields',      coords = vector3(1839.9, 4685.4, 43.8) },
        { label = 'Paleto Forest',         coords = vector3(-448.8, 6015.8, 31.5) },
        { label = 'Zancudo Airbase',       coords = vector3(-2075.0, 3169.0, 32.8) },
        { label = 'Chumash Coast',         coords = vector3(-3055.1, 1115.9, 11.6) },
        { label = 'Mount Josiah',          coords = vector3(-1432.3, 4578.5, 19.7) },
        { label = 'El Burro Heights',      coords = vector3(1375.9, -1553.2, 57.2) },
        { label = 'Los Santos Port',       coords = vector3(506.5, -3126.2, 6.0) },
    },

    crateModel   = 'prop_mil_crate_01',
    smokeModel   = 'prop_beach_fire',
    crateHeading = 0.0,

    cinematic = {
        heliModel        = 'cargobob',
        parachuteModel   = 'p_cs_parachute_s',
        spawnDistance    = 600.0,
        spawnAltitude    = 150.0,
        hoverAltitude    = 80.0,
        releaseHeightAGL = 80.0,
        approachSpeed    = 45.0,
        approachRadius   = 8.0,
        leaveDistance    = 900.0,
        approachSeconds  = 14.0,
        crateFallGravity = 0.18,
        parachuteFadeSec = 4.0,
        heliDespawnDelay = 25.0,
        smokeDurationSec = 300.0,
    },

    lootTable = {
        { chance = 0.55, items = {
            { name = 'bandage',    min = 2, max = 5 },
            { name = 'cloth',      min = 3, max = 8 },
            { name = 'painkillers',min = 1, max = 3 },
            { name = 'pistol_ammo',min = 8, max = 20 },
        }},
        { chance = 0.30, items = {
            { name = 'antibiotics',min = 1, max = 2 },
            { name = 'medkit',     min = 1, max = 2 },
            { name = 'smg_ammo',   min = 15, max = 35 },
            { name = 'rifle_ammo', min = 10, max = 25 },
        }},
        { chance = 0.15, items = {
            { name = 'weapon_smg',       min = 1, max = 1 },
            { name = 'weapon_pumpshotgun', min = 1, max = 1 },
            { name = 'weapon_carbinerifle', min = 1, max = 1 },
            { name = 'antidote',         min = 1, max = 1 },
        }},
    },

    itemsPerCrate = { min = 6, max = 10 },
}

Config.ZombieOutbreak = {
    zones = {
        { label = 'Sandy Shores Town',   coords = vector3(1961.6, 3744.0, 32.3) },
        { label = 'Paleto Bay Center',   coords = vector3(-163.9, 6361.0, 31.1) },
        { label = 'Grapeseed Main St',   coords = vector3(1662.7, 4860.3, 42.0) },
        { label = 'Chumash Village',     coords = vector3(-3133.8, 1079.8, 20.8) },
        { label = 'Strawberry Ave',      coords = vector3(245.2, -1776.1, 29.4) },
        { label = 'El Burro Heights',    coords = vector3(1355.4, -1654.0, 55.6) },
        { label = 'Harmony Repair',      coords = vector3(590.9, 2762.0, 42.0) },
        { label = 'Mirror Park',         coords = vector3(1121.8, -774.0, 57.5) },
    },

    radius        = 80.0,
    zombieCount   = { min = 18, max = 26 },
    spawnSpread   = 55.0,

    rewardCrate = {
        model    = 'prop_box_ammo02a',
        heading  = 0.0,
        itemsPerCrate = { min = 3, max = 6 },
        lootTable = {
            { chance = 0.60, items = {
                { name = 'pistol_ammo', min = 10, max = 24 },
                { name = 'bandage',     min = 1, max = 3 },
                { name = 'cloth',       min = 2, max = 5 },
            }},
            { chance = 0.30, items = {
                { name = 'smg_ammo',    min = 15, max = 30 },
                { name = 'antibiotics', min = 1, max = 2 },
                { name = 'medkit',      min = 1, max = 1 },
            }},
            { chance = 0.10, items = {
                { name = 'rifle_ammo',  min = 15, max = 30 },
                { name = 'antidote',    min = 1, max = 1 },
            }},
        },
    },
}

Config.ConvoyAmbush = {
    routes = {
        { label = 'Route 68 Convoy',    start = vector3(1200.0, 2700.0, 38.0),  heading = 90.0  },
        { label = 'Great Ocean Hwy',    start = vector3(-2400.0, 2300.0, 34.0), heading = 320.0 },
        { label = 'Paleto Blvd',        start = vector3(-600.0, 6400.0, 30.0),  heading = 180.0 },
        { label = 'Senora Fwy South',   start = vector3(2500.0, 1200.0, 55.0),  heading = 210.0 },
        { label = 'Los Santos Freeway', start = vector3(800.0, -800.0, 45.0),   heading = 0.0   },
    },

    vehicles = {
        lead   = 'insurgent',
        cargo  = 'mule3',
        escort = 'insurgent2',
    },

    zombieCount = { min = 12, max = 20 },
    zombieSpread = 25.0,
    radius = 60.0,

    lootTable = {
        { chance = 0.40, items = {
            { name = 'rifle_ammo',   min = 20, max = 50 },
            { name = 'smg_ammo',     min = 20, max = 40 },
            { name = 'shotgun_ammo', min = 10, max = 25 },
        }},
        { chance = 0.35, items = {
            { name = 'WEAPON_CARBINERIFLE',  min = 1, max = 1 },
            { name = 'WEAPON_COMBATSHOTGUN', min = 1, max = 1 },
            { name = 'medkit',               min = 2, max = 3 },
        }},
        { chance = 0.20, items = {
            { name = 'WEAPON_ASSAULTRIFLE_MK2', min = 1, max = 1 },
            { name = 'blueprint_rifle_ammo',    min = 1, max = 1 },
            { name = 'antidote',                min = 1, max = 2 },
        }},
        { chance = 0.05, items = {
            { name = 'WEAPON_RPG', min = 1, max = 1 },
        }},
    },
    itemsPerCrate = { min = 4, max = 8 },
}

Config.AirdropCrash = {
    crashSites = {
        { label = 'Raton Canyon',    coords = vector3(-1200.0, 4500.0, 25.0) },
        { label = 'Mt. Gordo',       coords = vector3(2600.0, 6200.0, 50.0) },
        { label = 'Grand Senora',    coords = vector3(2000.0, 3000.0, 45.0) },
        { label = 'Tongva Hills',    coords = vector3(-1800.0, 1800.0, 100.0) },
        { label = 'Cassidy Creek',   coords = vector3(-500.0, 4600.0, 90.0) },
        { label = 'Braddock Pass',   coords = vector3(800.0, 2500.0, 60.0) },
    },

    planeModel = 'titan',
    radius = 70.0,
    debrisCount = { min = 5, max = 8 },

    zombieCount = { min = 10, max = 16 },
    zombieSpread = 40.0,

    lootTable = {
        { chance = 0.35, items = {
            { name = 'rifle_ammo',   min = 30, max = 60 },
            { name = 'smg_ammo',     min = 30, max = 50 },
            { name = 'medkit',       min = 2, max = 3 },
            { name = 'antibiotics',  min = 1, max = 3 },
        }},
        { chance = 0.30, items = {
            { name = 'WEAPON_SPECIALCARBINE', min = 1, max = 1 },
            { name = 'WEAPON_SMG_MK2',       min = 1, max = 1 },
            { name = 'painkillers',           min = 2, max = 4 },
        }},
        { chance = 0.25, items = {
            { name = 'blueprint_smg_ammo',    min = 1, max = 1 },
            { name = 'blueprint_medkit',      min = 1, max = 1 },
            { name = 'WEAPON_COMBATMG_MK2',   min = 1, max = 1 },
        }},
        { chance = 0.10, items = {
            { name = 'WEAPON_MINIGUN',       min = 1, max = 1 },
            { name = 'blueprint_shotgun_ammo', min = 1, max = 1 },
        }},
    },
    itemsPerCrate = { min = 5, max = 9 },
}

Config.SurvivorRescue = {
    locations = {
        { label = 'Vespucci House',     coords = vector3(-1150.0, -1420.0, 28.0) },
        { label = 'Davis Warehouse',    coords = vector3(300.0, -1950.0, 26.0) },
        { label = 'Rockford Hills',     coords = vector3(-300.0, -150.0, 45.0) },
        { label = 'La Mesa Garage',     coords = vector3(820.0, -1000.0, 35.0) },
        { label = 'Burton Mall',        coords = vector3(-150.0, -350.0, 40.0) },
        { label = 'East LS Compound',   coords = vector3(1300.0, -1800.0, 55.0) },
    },

    survivorModels = {
        'a_m_m_tramp_01',
        'a_f_m_skidrow_01',
        'a_m_m_socenlat_01',
        'a_f_m_bodybuild_01',
        'a_m_m_hillbilly_01',
    },

    radius = 30.0,
    zombieWaves = 3,
    zombiesPerWave = { min = 5, max = 8 },
    waveInterval = 20000,

    rewardLoot = {
        { chance = 0.50, items = {
            { name = 'medkit',       min = 2, max = 4 },
            { name = 'antidote',     min = 1, max = 2 },
            { name = 'clean_water',  min = 2, max = 4 },
            { name = 'canned_food',  min = 2, max = 4 },
        }},
        { chance = 0.30, items = {
            { name = 'WEAPON_CARBINERIFLE',   min = 1, max = 1 },
            { name = 'rifle_ammo',            min = 30, max = 60 },
            { name = 'blueprint_medkit',      min = 1, max = 1 },
        }},
        { chance = 0.15, items = {
            { name = 'WEAPON_COMBATSHOTGUN',  min = 1, max = 1 },
            { name = 'blueprint_antidote',    min = 1, max = 1 },
        }},
        { chance = 0.05, items = {
            { name = 'WEAPON_TECPISTOL',      min = 1, max = 1 },
        }},
    },
    itemsPerReward = { min = 3, max = 6 },
}

Config.Extraction = {
    zones = {
        { label = 'Zancudo Approach',    coords = vector3(-2100.0, 3300.0, 32.0) },
        { label = 'Sandy Shore Heli',    coords = vector3(1800.0, 3600.0, 35.0) },
        { label = 'Paleto Dock',         coords = vector3(-350.0, 6400.0, 30.0) },
        { label = 'LSIA Terminal',       coords = vector3(-1100.0, -2700.0, 14.0) },
        { label = 'Del Perro Beach',     coords = vector3(-1500.0, -900.0, 20.0) },
    },

    radius = 40.0,
    holdTime = 120,
    zombieCount = { min = 20, max = 30 },
    zombieSpread = 50.0,

    heliModel = 'buzzard2',

    lootTable = {
        { chance = 0.35, items = {
            { name = 'rifle_ammo',    min = 30, max = 70 },
            { name = 'shotgun_ammo',  min = 15, max = 30 },
            { name = 'medkit',        min = 2, max = 4 },
        }},
        { chance = 0.35, items = {
            { name = 'WEAPON_ASSAULTRIFLE_MK2', min = 1, max = 1 },
            { name = 'WEAPON_COMBATSHOTGUN',    min = 1, max = 1 },
            { name = 'antidote',                min = 1, max = 2 },
        }},
        { chance = 0.25, items = {
            { name = 'blueprint_rifle_ammo',  min = 1, max = 1 },
            { name = 'WEAPON_SPECIALCARBINE', min = 1, max = 1 },
        }},
        { chance = 0.05, items = {
            { name = 'WEAPON_MINIGUN', min = 1, max = 1 },
            { name = 'WEAPON_RPG',     min = 1, max = 1 },
        }},
    },
    itemsPerReward = { min = 5, max = 10 },
}
