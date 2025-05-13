fx_version 'cerulean'
game 'gta5'

author 'PerfQ'
description 'esx_economyreworked - Economy framework for ESX addons'
version '1.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@es_extended/locale.lua',
    'shared/config.lua',
    'locales/*.lua'
}

client_scripts {
    'client/main.lua',
    'client/menus.lua',
    'client/treasury_ui.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/api.lua',
    'server/npc.lua',
    'server/crime.lua',
    'server/treasury.lua'
}

dependencies {
    'oxmysql',
    'es_extended'
}

lua54 'yes'