fx_version 'cerulean'
game 'gta5'

author 'PerfQ'
description 'esx_economyreworked - Business management framework'
version '1.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    '@es_extended/locale.lua',
    'shared/config.lua',
    'locales/*.lua'
}

client_scripts {
    'client/api.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/api.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql',
    'es_extended'
}

lua54 'yes'