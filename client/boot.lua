--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Last client script: opens the scene once ug-core is ready and the player exists.

local Flow = UgMc.Internal.Flow

local RESOURCE = GetCurrentResourceName()
local READY_TIMEOUT = 60000

UgCore.Network.Register('Open', function()
    CreateThread(function()
        Flow.Open(true)
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == RESOURCE and Flow.IsOpen() then
        Flow.Reset()
    end
end)

CreateThread(function()
    -- Black from the first frame, so the world never shows before the intro.
    DoScreenFadeOut(0)

    if not UgCore.Lifecycle.Await(UgCore.Enums.Lifecycle.Ready, READY_TIMEOUT) then
        print('[ug-multicharacter] ug-core did not become ready.')
        DoScreenFadeIn(500)

        return
    end

    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(100)
    end

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    -- A restart of this resource while playing MUST NOT pull the player out of the world.
    if UgCore.LocalPlayer.IsLoaded() then
        DoScreenFadeIn(500)

        return
    end

    Flow.Open(false)
end)
