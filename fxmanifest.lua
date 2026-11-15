--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@diagnostic disable: undefined-global

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ug-multicharacter'
author 'UgCore Framework & Contributors'
version '1.0.0' -- x-release-please-version
description 'Character selection, creation and spawning for UgCore'
repository 'https://github.com/ugcore-project/ug-multicharacter'

ugcore_version '1.0.0'
uglib_version '1.0.0'

dependencies {
    '/onesync',
    'ug-core',
    'ug-lib',
}

shared_scripts {
    '@ug-core/import.lua',
    '@ug-lib/import.lua',
    'shared/init.lua',
    'shared/enums.lua',
}

server_scripts {
    'server/config.lua',
    'server/state.lua',
    'server/characters.lua',
    'server/spawn.lua',
    'server/commands.lua',
    'server/boot.lua',
}

client_scripts {
    'client/camera.lua',
    'client/cinematic.lua',
    'client/appearance.lua',
    'client/scene.lua',
    'client/nui.lua',
    'client/spawn.lua',
    'client/flow.lua',
    'client/boot.lua',
}

ui_page 'web/dist/index.html'

files {
    'locales/*.json',
    'web/dist/index.html',
    'web/dist/assets/*',
}
