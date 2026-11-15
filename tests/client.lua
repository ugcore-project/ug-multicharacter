--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@type TestHelpers
local H = dofile('tests/helpers.lua')

local HOME = vector4(-1037.5, -2737.25, 20.17, 330.0)

---@param a number
---@param b number
---@param message? string
local function near(a, b, message)
    H.Assert(math.abs(a - b) < 0.01, ('%s: %s is not %s'):format(message or 'not near', a, b))
end

---The server defaults, which clients never load.
---@return table
local function defaults()
    return H.Defaults()
end

---The cinematic List sends: the defaults with `changes` applied.
---@param cinematic table
---@param changes table
---@return table
local function withCinematic(cinematic, changes)
    for key, value in pairs(changes) do
        cinematic[key] = value
    end

    return cinematic
end

---What List answers in these tests: the defaults, with `characters`.
---@param characters? table[]
---@return table
local function listAnswer(characters)
    local config = defaults()

    return {
        ok = true,
        characters = characters or {},
        slots = 4,
        fields = config.fields,
        ageRange = config.ageRange,
        scene = config.scene,
        cinematic = withCinematic(config.cinematic, {
            timecycle = 'cinema',
            title = 'Test',
        }),
        -- No spawn points: these tests take the direct way in. tests/nui.lua covers the picker.
        spawn = {
            points = {},
            firstSpawn = config.spawn.firstSpawn,
            default = config.spawn.default,
        },
        appearance = config.appearance,
        allowDelete = true,
        sounds = true,
        soundEffects = config.soundEffects,
        theme = config.theme,
        layout = config.layout,
        details = config.details,
    }
end

---Loads the client without opening the scene.
local function start()
    H.Reset()
    H.LocalLoaded = true
    H.Load('client')
    H.Natives = {}
end

H.Test('Easing curves start at 0, end at 1 and never go back', function()
    start()

    local Camera = UgMc.Internal.Camera

    for _, ease in pairs(UgMc.Enums.Ease) do
        H.Equal(Camera.Ease(ease, 0), 0, ease)
        H.Equal(Camera.Ease(ease, 1), 1, ease)

        local last = 0

        for step = 1, 20 do
            local value = Camera.Ease(ease, step / 20)

            H.Assert(value >= last, ease .. ' goes back')
            last = value
        end
    end

    near(Camera.Ease(UgMc.Enums.Ease.InOut, 0.5), 0.5, 'InOut is centered')
    H.Equal(Camera.Ease(UgMc.Enums.Ease.Out, 2), 1, 'clamped')
end)

H.Test('Angles turn the short way, LookAt and Forward follow the game convention', function()
    start()

    local Camera = UgMc.Internal.Camera

    near(Camera.LerpAngle(350, 10, 0.5) % 360, 0, 'through north')
    near(Camera.LerpAngle(10, 350, 0.5) % 360, 0, 'back through north')

    local east = Camera.LookAt(vector3(0, 0, 0), vector3(10, 0, 0))

    near(east.z, -90, 'heading east')
    near(east.x, 0, 'level')
    near(Camera.LookAt(vector3(0, 0, 0), vector3(0, 10, 10)).x, 45, 'pitch up')

    local x, y = Camera.Forward(90)

    near(x, -1, 'heading 90 faces west')
    near(y, 0)
end)

H.Test('The default intro starts high and far, fades in, and ends on the rest shot', function()
    start()

    local rest = defaults().scene.camera
    local shots = UgMc.Internal.Cinematic.Intro(rest)

    H.Equal(#shots, 3)
    H.Equal(shots[1].fadeIn, true)
    H.Equal(shots[1].letterbox, true)
    H.Assert(shots[1].from.coords.z > rest.coords.z + 50, 'establishing shot is high')
    H.Equal(shots[#shots].to, rest)
    H.Equal(shots[#shots].letterbox, false)

    local total = 0

    for _, shot in ipairs(shots) do
        total = total + shot.duration
    end

    H.Assert(total >= 6000 and total <= 9000, 'the intro lasts 6 to 8 s, got ' .. total)
end)

H.Test('Focus frames a ped from the front at chest height', function()
    start()

    -- Heading 90 faces west, so the camera stands west of the ped and looks east.
    local pose = UgMc.Internal.Cinematic.Focus(vector4(10.0, 20.0, 30.0, 90.0), {
        distance = 2.4,
        height = 0.75,
        fov = 38.0,
    })

    near(pose.coords.x, 7.6, 'in front')
    near(pose.coords.y, 20.0)
    near(pose.rotation.z, -90, 'looks back at the ped')
    H.Assert(pose.rotation.x < 0, 'looks slightly down')
    H.Equal(pose.fov, 38.0)
end)

H.Test('Shots move the camera along the eased curve, and a skip lands on the last pose', function()
    start()

    local Cinematic = UgMc.Internal.Cinematic
    local from = {
        coords = vector3(0, 0, 0),
        rotation = vector3(0, 0, 0),
        fov = 40.0,
    }
    local to = {
        coords = vector3(100, 0, 0),
        rotation = vector3(0, 0, 90),
        fov = 60.0,
    }
    local finished = nil

    CreateThread(function()
        finished = Cinematic.Play({
            {
                from = from,
                to = to,
                duration = 1000,
                ease = UgMc.Enums.Ease.Linear,
            },
        })
    end)

    H.Advance(500)

    local moves = H.CallsOf('SetCamCoord')
    local x = moves[#moves].args[2]

    H.Assert(x > 40 and x < 60, 'half way, got ' .. x)
    H.Equal(finished, nil)

    H.Advance(600)
    H.Equal(finished, true)

    local fovs = H.CallsOf('SetCamFov')

    H.Equal(fovs[#fovs].args[2], 60.0)

    local skip = false

    CreateThread(function()
        finished = Cinematic.Play({
            {
                from = from,
                to = to,
                duration = 5000,
            },
        }, function()
            return skip
        end)
    end)

    H.Advance(100)
    skip = true
    H.Advance(32)

    H.Equal(finished, false)
    H.Equal(UgMc.Internal.Camera.Get(), to)
end)

H.Test('Letterbox bars slide in and out, and stay off when the owner turns them off', function()
    start()

    local Cinematic = UgMc.Internal.Cinematic

    Cinematic.Configure(defaults().cinematic)
    Cinematic.Letterbox(UgMc.Enums.Letterbox.Full)
    H.Advance(1000)

    local bars = H.CallsOf('DrawRect')

    H.Assert(#bars > 0, 'bars drawn')
    near(bars[#bars].args[4], (1 - (16 / 9) / 2.39) / 2, 'full height')

    Cinematic.Letterbox(UgMc.Enums.Letterbox.None)
    H.Advance(1000)
    H.Natives = {}
    H.Advance(100)
    H.Equal(#H.CallsOf('DrawRect'), 0, 'no bars once gone')

    Cinematic.Configure(withCinematic(defaults().cinematic, {
        letterbox = false,
    }))
    Cinematic.Letterbox(UgMc.Enums.Letterbox.Full)
    H.Advance(500)
    H.Equal(#H.CallsOf('DrawRect'), 0)
end)

H.Test('The scene builds one ped per slot, faint placeholders, and cleans up', function()
    start()

    local Scene = UgMc.Internal.Scene
    local answer = listAnswer({
        {
            id = 1,
            name = 'Ana',
            data = {
                model = 'mp_f_freemode_01',
            },
        },
        {
            id = 2,
            name = 'Rui',
            data = {
                model = 'broken_model',
            },
        },
    })

    H.BrokenModels = { 'broken_model' }

    CreateThread(function()
        Scene.Open(answer)
    end)

    H.Equal(Scene.Count(), 4)
    H.Equal(#H.CallsOf('CreatePed'), 4)
    H.Equal(H.CallsOf('CreatePed')[1].args[2], 'mp_f_freemode_01')
    H.Equal(#H.CallsOf('SetEntityAlpha'), 3, 'two empty slots and the model that failed')
    H.Equal(H.CallsOf('NetworkOverrideClockTime')[1].args, { 19, 45, 0 })
    H.Equal(Scene.Slot(1).character.name, 'Ana')
    H.Equal(Scene.Slot(3).character, nil)

    local camera = answer.scene.camera.coords
    local focus = H.CallsOf('SetFocusPosAndVel')

    H.Equal(#focus, 1, 'streaming follows the scene, wherever the hidden ped ends up')
    H.Equal({ focus[1].args[1], focus[1].args[2], focus[1].args[3] }, { camera.x, camera.y, camera.z })
    H.Equal(#H.CallsOf('ClearFocus'), 0)

    Scene.Close()

    H.Equal(#H.CallsOf('DeletePed'), 4)
    H.Equal(#H.CallsOf('NetworkClearClockTimeOverride'), 1)
    H.Equal(#H.CallsOf('ClearFocus'), 1, 'streaming goes back to the player')
    H.Equal(Scene.Count(), 0)
end)

H.Test('From join to the world: intro, focus, select, place, arrive, hand-over', function()
    H.Reset()

    local character = {
        id = 4,
        name = 'Ana',
        data = {
            model = 'mp_f_freemode_01',
        },
        deathState = 'Alive',
    }

    H.Respond.List = function()
        return listAnswer({ character })
    end
    H.Respond.Play = function(characterId, spawnId)
        H.Equal({ characterId, spawnId }, { 4, 'last' })

        return {
            ok = true,
            destination = HOME,
            deathState = 'Alive',
        }
    end
    H.Respond.Arrived = function()
        return {
            ok = true,
        }
    end

    local lines = H.Load('client')

    H.Equal(H.Natives[1], {
        name = 'DoScreenFadeOut',
        args = { 0 },
    }, 'black from the first frame')
    H.ExpectLine(lines, 'Scene opened in')

    H.Capture(function()
        H.Advance(9000)
    end)

    H.Equal(H.Faded, false, 'faded in')
    H.Equal(#H.CallsOf('SetTimecycleModifier'), 1)

    H.PostNui('select', {
        index = 1,
    })
    lines = H.Capture(function()
        H.Advance(8000)
    end)

    H.Equal({ H.Requests[1].name, H.Requests[2].name, H.Requests[3].name }, { 'List', 'Play', 'Arrived' })
    H.Equal(#H.CallsOf('DeletePed'), 4, 'lineup removed while black')
    H.Equal(H.CallsOf('SetPlayerModel')[1].args[2], 'mp_f_freemode_01')
    H.Equal(H.CallsOf('SetEntityCoordsNoOffset')[2].args, { 1, HOME.x, HOME.y, HOME.z, false, false, false })

    local renders = H.CallsOf('RenderScriptCams')

    H.Equal(renders[#renders].args, { false, true, 1500, true, true }, 'eased hand-over to the game camera')
    H.Equal(#H.CallsOf('ClearTimecycleModifier'), 1)

    local freezes = H.CallsOf('FreezeEntityPosition')

    H.Equal(freezes[#freezes].args, { 1, false }, 'the player moves again')
    H.ExpectLine(lines, 'Character loaded in')
    H.Equal(UgMc.Internal.Flow.IsOpen(), false)
end)

H.Test('An arrival retry places the player again at the destination the server sends', function()
    H.Reset()

    local character = {
        id = 4,
        name = 'Ana',
        data = {
            model = 'mp_f_freemode_01',
        },
        deathState = 'Alive',
    }
    local arrivals = 0
    local corrected = vector4(HOME.x + 1, HOME.y, HOME.z, HOME.w)

    H.Respond.List = function()
        return listAnswer({ character })
    end
    H.Respond.Play = function()
        return {
            ok = true,
            destination = HOME,
            deathState = 'Alive',
        }
    end
    H.Respond.Arrived = function()
        arrivals = arrivals + 1

        return arrivals == 1 and {
            ok = false,
            error = 'invalid_args',
            retry = true,
            destination = corrected,
        } or {
            ok = true,
        }
    end

    H.Load('client')
    H.Capture(function()
        H.Advance(9000)
        H.PostNui('select', {
            index = 1,
        })
        H.Advance(9000)
    end)

    H.Equal(arrivals, 2)

    local placements = H.CallsOf('SetEntityCoordsNoOffset')

    H.Equal(placements[#placements].args[2], corrected.x)
end)

H.Test('A refused Play goes back to the lineup', function()
    H.Reset()

    local character = {
        id = 4,
        name = 'Ana',
        data = {
            model = 'mp_f_freemode_01',
        },
        deathState = 'Alive',
    }

    H.Respond.List = function()
        return listAnswer({ character })
    end
    H.Respond.Play = function()
        return {
            ok = false,
            error = 'no_permission',
        }
    end

    H.Load('client')

    local lines = H.Capture(function()
        H.Advance(9000)
        H.PostNui('select', {
            index = 1,
        })
        H.Advance(6000)
    end)

    H.ExpectLine(lines, 'Could not play: no_permission.')
    H.Equal(H.Requests[3].name, 'List', 'the scene opened again')
    H.Equal(UgMc.Internal.Flow.IsOpen(), true)
end)

H.Test('A player already in the world is left alone, and the Open event reopens the scene', function()
    start()

    H.Equal(#H.Requests, 0)
    H.Equal(H.Faded, false)

    H.Respond.List = function()
        return listAnswer({})
    end

    H.Capture(function()
        H.ClientEvents.Open()
        H.Advance(3000)
    end)

    H.Equal(H.Requests[1].name, 'List')
    H.Equal(UgMc.Internal.Flow.IsOpen(), true)
end)

H.Test('Stopping the resource puts everything back', function()
    start()

    H.Respond.List = function()
        return listAnswer({})
    end

    H.Capture(function()
        H.ClientEvents.Open()
        H.Advance(3000)
    end)

    H.Natives = {}
    H.TriggerEvent('onResourceStop', 0, 'ug-multicharacter')

    H.Equal(#H.CallsOf('DestroyCam'), 1)
    H.Equal(#H.CallsOf('DeletePed'), 4)
    H.Equal(UgMc.Internal.Flow.IsOpen(), false)
    H.Equal(H.CallsOf('SetEntityVisible')[1].args, { 1, true, false })
end)

H.Done()
