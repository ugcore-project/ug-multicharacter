--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Last server script: loads config, waits for ug-core and checks what this resource needs from it.

local Config = UgMc.Internal.Config
local Logger = UgCore.Logger

local RESOURCE = GetCurrentResourceName()
local READY_TIMEOUT = 60000

---Set once config and ug-core are both usable. Nothing registers before.
---@type boolean
UgMc.Internal.Ready = false

---@return string? problem why this resource cannot run
local function checkCore()
    if not UgCore.Lifecycle.Await(UgCore.Enums.Lifecycle.Ready, READY_TIMEOUT) then
        return 'ug-core did not become ready. Check its console output.'
    end

    if not UgCore.Modules.IsEnabled('characters') then
        return "ug-core's characters module is disabled. Enable it in ug-core's config/modules.lua."
    end

    local slots = UgCore.Config.Get('characters', 'maxCharacters')
    local scene = Config.Get().scene

    if #scene.slots < slots then
        return ('config.lua: scene has %d slots, ug-core maxCharacters is %d. Add slots or lower maxCharacters.'):format(#scene.slots, slots)
    end

    return nil
end

CreateThread(function()
    local ok, errors = Config.Load()

    if not ok then
        for _, message in ipairs(errors) do
            Logger.Error(message)
        end

        Logger.Error('Config invalid: %d error(s). ug-multicharacter stays idle.', #errors)

        return
    end

    local problem = checkCore()

    if problem then
        Logger.Error(problem)
        Logger.Error('ug-multicharacter stays idle.')

        return
    end

    UgMc.Internal.Characters.Register()
    UgMc.Internal.Spawn.Register()
    UgMc.Internal.Commands.Register()
    UgMc.Internal.Ready = true

    local config = Config.Get()

    print(('[ug-multicharacter] v%s ready: %d spawn points, %d slots.'):format(
        GetResourceMetadata(RESOURCE, 'version', 0) or '?',
        #config.spawn.points,
        UgCore.Config.Get('characters', 'maxCharacters')
    ))
end)
