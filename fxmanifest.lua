fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'corex-events'
description 'COREX Dynamic World Events System'
author 'ABUGIZA'
version '2.0.0'

shared_scripts {
    'config.lua',
    'shared/events.lua'
}

server_scripts {
    'server/inventory_bridge.lua',
    'server/main.lua',
    'server/scheduler.lua',
    'server/loot_utils.lua',
    'server/zombie_hordes.lua',
    'server/events/supply_drop.lua',
    'server/events/zombie_outbreak.lua',
    'server/events/convoy_ambush.lua',
    'server/events/airdrop_crash.lua',
    'server/events/survivor_rescue.lua',
    'server/events/extraction.lua'
}

client_scripts {
    'client/main.lua',
    'client/ui.lua',
    'client/events/supply_drop.lua',
    'client/events/zombie_outbreak.lua',
    'client/events/convoy_ambush.lua',
    'client/events/airdrop_crash.lua',
    'client/events/survivor_rescue.lua',
    'client/events/extraction.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

-- No inventory is named here at all, in a dependency or in an include. This
-- resource asks CoreX for whichever
-- inventory is installed, so stopping that one must not stop this one.
dependencies {
    'corex-core',
    'corex-loot',
    'corex-zombies'
}
