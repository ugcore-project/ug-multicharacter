--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@type TestHelpers
local H = dofile('tests/helpers.lua')

local HOME = vector4(-1037.5, -2737.25, 20.17, 330.0)

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

---@param characters table[]
---@return table
local function listAnswer(characters)
    local config = defaults()

    return {
        ok = true,
        characters = characters,
        slots = 4,
        fields = config.fields,
        ageRange = config.ageRange,
        scene = config.scene,
        cinematic = withCinematic(config.cinematic, {
            title = 'Los Santos RP',
        }),
        spawn = {
            points = config.spawn.points,
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

---Opens the scene with one character, the page ready.
---@return table character
local function open()
    H.Reset()

    local character = {
        id = 4, name = 'Ana Silva', data = {
            model = 'mp_f_freemode_01',
            birthDate = '1995-04-12',
        },
        deathState = 'Downed', lastPlayed = 1791400000, position = {
            x = HOME.x,
            y = HOME.y,
            z = HOME.z,
        },
    }

    H.Respond.List = function()
        return listAnswer({ character })
    end
    H.NativeReturns.GetStreetNameAtCoord = 1234
    H.NativeReturns.GetStreetNameFromHashKey = 'Vespucci Boulevard'

    H.Capture(function()
        H.Load('client')
        H.PostNui('ready', {})
    end)

    return character
end

---Reads `UgMc.Enums.<name>` values against an `export const <name> = { ... }` block of protocol.ts.
---@param source string
---@param name string
---@return table<string, string>
local function tsEnum(source, name)
    local block = assert(source:match('export const ' .. name .. ' = (%b{})'), name .. ' missing in protocol.ts')
    local values = {}

    for key, value in block:gmatch('(%w+): "([^"]+)"') do
        values[key] = value
    end

    return values
end

H.Test('Lua and the page agree on every action, callback and screen', function()
    H.Reset()
    H.Load('client')

    local handle = assert(io.open('web/src/types/protocol.ts', 'rb'))
    local source = handle:read('a')

    handle:close()

    for _, name in ipairs({
        'NuiAction',
        'NuiCallback',
        'Screen',
        'ResultKind',
        'FieldType',
        'Side',
        'Place',
        'Detail',
    }) do
        H.Equal(tsEnum(source, name), UgMc.Enums[name], name)
    end
end)

H.Test('Messages wait for the page, then config comes first with ug-lib theme and labels', function()
    H.Reset()
    H.Respond.List = function()
        return listAnswer({})
    end

    H.Capture(function()
        H.Load('client')
    end)

    H.Equal(#H.PageMessages(), 0, 'nothing sent before ready')

    GlobalState['ug-lib:Config'] = {
        theme = {
            mode = 'light',
            colors = {},
            radius = '0.5rem',
            font = 'Inter',
            scale = 1,
        },
    }
    H.Equal(H.PostNui('ready', {}), {
        ok = true,
    })

    local messages = H.PageMessages()

    H.Equal(messages[1].action, 'config')
    H.Equal(messages[1].payload.theme.mode, 'light')
    H.Equal(messages[1].payload.labels.play, 'label:page.play')
    H.Equal(messages[1].payload.locale, 'en')
    H.Equal(messages[2].action, 'form', 'queued messages follow')
    H.Equal(messages[2].payload.fields[1].name, 'firstName')
    H.Equal(messages[2].payload.fields[1].label, 'label:fields.firstName', 'labels come from the locale')
    H.Equal(messages[2].payload.fields[4].options[2].label, 'label:options.sex.female')
    H.Equal(messages[2].payload.models, { 'mp_m_freemode_01', 'mp_f_freemode_01' })
    H.Equal(messages[3].action, 'open')
end)

H.Test('Cards show the name, birth date, last played, street and death state, never ids', function()
    open()

    local slots = H.LastPage('open').slots

    H.Equal(#slots, 4)
    H.Equal(slots[1].character, {
        name = 'Ana Silva', birthDate = '1995-04-12', lastPlayed = 1791400000, street = 'Vespucci Boulevard', deathState = 'Downed',
    })
    H.Equal(slots[2], {})
end)

H.Test('Intro: keyboard focus, title card, skip; then selection with the mouse', function()
    open()

    H.Equal(H.LastPage('screen'), {
        screen = 'intro',
    })
    H.Equal(H.CallsOf('SetNuiFocus')[1].args, { true, false }, 'keys only during the intro')

    H.Advance(1500)
    H.Equal(H.LastPage('title'), {
        text = 'Los Santos RP',
        visible = true,
    })

    H.Equal(H.PostNui('hover', {
        index = 2,
    }), {
        ok = true,
    })
    H.Equal(#H.CallsOf('SetCamCoord') > 0, true)

    H.PostNui('skip', {})
    H.Advance(500)

    H.Equal(H.LastPage('screen'), {
        screen = 'select',
    })
    H.Equal(H.LastPage('visible'), {
        visible = true,
    })
    H.Equal(H.LastPage('focus'), {
        index = 1,
    })

    local focus = H.CallsOf('SetNuiFocus')

    H.Equal(focus[#focus].args, { true, true }, 'cursor for the selection')
end)

H.Test('Callback bodies are checked: integer slots in the lineup only', function()
    open()
    H.Advance(9000)

    for _, body in ipairs({
        {
            index = 0,
        },
        {
            index = 5,
        },
        {
            index = 1.5,
        },
        {
            index = '1',
        },
        'nope',
        {},
    }) do
        H.Equal(H.PostNui('hover', body), {
            ok = false,
        })
        H.Equal(H.PostNui('select', body), {
            ok = false,
        })
    end

    H.Equal(#H.Requests, 1, 'only List reached the server')
end)

H.Test('Too many callbacks in one second are refused', function()
    open()
    H.Advance(9000)

    local refused = 0

    for _ = 1, 40 do
        if not H.PostNui('hover', {
            index = 1,
        }).ok then
            refused = refused + 1
        end
    end

    H.Equal(refused, 10)
end)

H.Test('Selecting a character plays it', function()
    open()
    H.Respond.Play = function()
        return {
            ok = true,
            destination = HOME,
            deathState = 'Downed',
        }
    end
    H.Respond.Arrived = function()
        return {
            ok = true,
        }
    end

    H.Advance(9000)
    H.PostNui('select', {
        index = 1,
    })
    H.Advance(500)
    H.Equal(H.LastPage('screen'), {
        screen = 'busy',
    })
    H.Equal(H.LastPage('visible'), {
        visible = false,
    })

    H.Capture(function()
        H.Advance(8000)
    end)

    H.Equal(H.Requests[2].name, 'Play')
    H.Equal(H.PageMessages()[#H.PageMessages()].action, 'close')
end)

---Opens the scene and the creation screen on slot 2.
---@return table character the one in slot 1
local function openCreate()
    local character = open()

    H.Advance(9000)
    H.Natives = {}
    H.PostNui('select', {
        index = 2,
    })
    H.Advance(1000)

    return character
end

H.Test('An empty slot opens creation with a preview body and a full-body shot', function()
    openCreate()

    H.Equal(H.LastPage('screen'), {
        screen = 'create',
    })
    H.Equal(H.CallsOf('DeletePed')[1].args[1], 102, 'the placeholder of slot 2 goes')
    H.Equal(H.CallsOf('CreatePed')[1].args[2], 'mp_m_freemode_01', 'the first offered model')
    H.Equal(#H.CallsOf('SetEntityAlpha'), 0, 'a real body, not a faint one')

    H.Natives = {}
    H.Equal(H.PostNui('model', {
        model = 'mp_f_freemode_01',
    }), {
        ok = true,
    })
    H.Equal(H.CallsOf('CreatePed')[1].args[2], 'mp_f_freemode_01')

    H.Equal(H.PostNui('model', {
        model = 'a_c_chop',
    }), {
        ok = false,
    }, 'not offered')
    H.Equal(H.PostNui('model', {
        model = 5,
    }), {
        ok = false,
    })
end)

H.Test('Forged submissions never reach the server', function()
    openCreate()

    local valid = {
        firstName = 'Ana',
        lastName = 'Silva',
        birthDate = '1995-04-12',
        sex = 'female',
    }

    for label, body in pairs({
        unknownField = {
            fields = {
                firstName = 'Ana',
                admin = 'yes',
            },
            model = 'mp_m_freemode_01',
        },
        notAString = {
            fields = {
                firstName = 5,
            },
            model = 'mp_m_freemode_01',
        },
        tooLong = {
            fields = {
                firstName = ('a'):rep(300),
            },
            model = 'mp_m_freemode_01',
        },
        badModel = {
            fields = valid,
            model = 'a_c_chop',
        },
        noFields = {
            model = 'mp_m_freemode_01',
        },
        notATable = 'Ana',
    }) do
        H.Equal(H.PostNui('submit', body), {
            ok = false,
        }, label)
    end

    H.Equal(#H.Requests, 1, 'only List')
end)

H.Test('A created character joins the lineup and gets the focus', function()
    local character = openCreate()
    local fields = {
        firstName = 'Rui',
        lastName = 'Costa',
        birthDate = '1990-01-01',
        sex = 'male',
    }

    H.Respond.Create = function(input)
        H.Equal(input, {
            fields = fields,
            model = 'mp_m_freemode_01',
        })

        return {
            ok = true,
            characterId = 9,
        }
    end
    H.Respond.List = function()
        return listAnswer({
            character,
            {
                id = 9,
                name = 'Rui Costa',
                data = {
                    model = 'mp_m_freemode_01',
                },
                deathState = 'Alive',
            },
        })
    end

    H.Equal(H.PostNui('submit', {
        fields = fields,
        model = 'mp_m_freemode_01',
    }), {
        ok = true,
    })
    H.Advance(2000)

    H.Equal(H.LastPage('result'), {
        kind = 'create',
        ok = true,
    })
    H.Equal(H.LastPage('screen'), {
        screen = 'select',
    })
    H.Equal(H.LastPage('focus'), {
        index = 2,
    })
    H.Equal(H.LastPage('open').slots[2].character.name, 'Rui Costa')
end)

H.Test('A refused create keeps the form open with the error', function()
    openCreate()

    H.Respond.Create = function()
        return {
            ok = false,
            error = 'no_permission',
        }
    end

    H.PostNui('submit', {
        fields = {
            firstName = 'Rui',
        },
        model = 'mp_m_freemode_01',
    })
    H.Advance(500)

    H.Equal(H.LastPage('result'), {
        kind = 'create',
        ok = false,
        error = 'no_permission',
    })
    H.Equal(H.LastPage('screen'), {
        screen = 'create',
    })
end)

H.Test('Cancel puts the placeholder back and returns to the selection', function()
    openCreate()
    H.Natives = {}

    H.PostNui('cancel', {})
    H.Advance(1000)

    H.Equal(H.LastPage('screen'), {
        screen = 'select',
    })
    H.Equal(#H.CallsOf('SetEntityAlpha'), 1, 'faint again')
end)

H.Test('Delete removes a character and refreshes, and only works on characters', function()
    local character = open()

    H.Advance(9000)

    H.PostNui('delete', {
        index = 2,
    })
    H.Advance(500)
    H.Equal(#H.Requests, 1, 'an empty slot has nothing to delete')

    H.Respond.Delete = function(characterId)
        H.Equal(characterId, character.id)

        return {
            ok = true,
        }
    end
    H.Respond.List = function()
        return listAnswer({})
    end

    H.PostNui('delete', {
        index = 1,
    })
    H.Advance(2000)

    H.Equal(H.Requests[2].name, 'Delete')
    H.Equal(H.LastPage('result'), {
        kind = 'delete',
        ok = true,
    })
    H.Equal(H.LastPage('open').slots[1], {})
end)

H.Test('locales/en.json has exactly the labels the page uses', function()
    H.Reset()
    H.Load('client')

    local handle = assert(io.open('locales/en.json', 'rb'))
    local source = handle:read('a')

    handle:close()

    local block = assert(source:match('"page"%s*:%s*(%b{})'))
    local inFile = {}

    for key in block:gmatch('"(%w+)"%s*:') do
        inFile[#inFile + 1] = key
    end

    local expected = { table.unpack(UgMc.Internal.Nui.LabelKeys) }

    table.sort(inFile)
    table.sort(expected)
    H.Equal(inFile, expected)
end)

---Opens the scene with an alive character that has a position, so the picker has places to offer.
---@return table character
local function openAlive()
    H.Reset()

    local character = {
        id = 4, name = 'Ana Silva', data = {
            model = 'mp_f_freemode_01',
        },
        deathState = 'Alive', position = {
            x = HOME.x,
            y = HOME.y,
            z = HOME.z,
        },
    }

    H.Respond.List = function()
        return listAnswer({ character })
    end
    H.NativeReturns.GetStreetNameAtCoord = 1234
    H.NativeReturns.GetStreetNameFromHashKey = 'Vespucci Boulevard'

    H.Capture(function()
        H.Load('client')
        H.PostNui('ready', {})
        H.Advance(9000)
    end)

    return character
end

H.Test('Picker options: one place for the downed, the dead and new arrivals sent to the default spawn', function()
    openAlive()

    local Picker = UgMc.Internal.Picker
    local config = defaults()
    local spawn = {
        points = config.spawn.points,
        firstSpawn = 'picker',
        default = config.spawn.default,
    }
    local label = function(key)
        return key
    end

    local ids = {}

    for index, option in ipairs(Picker.Options({
        deathState = 'Alive',
        position = {
            x = 1,
            y = 2,
            z = 3,
        },
    }, spawn, label)) do
        ids[index] = option.id
    end

    H.Equal(ids, { 'last', 'legion', 'sandy', 'paleto' })
    H.Equal(#Picker.Options({
        deathState = 'Downed',
        position = {
            x = 1,
            y = 2,
            z = 3,
        },
    }, spawn, label), 1)
    H.Equal(#Picker.Options({
        deathState = 'Dead',
    }, spawn, label), 1)

    local first = Picker.Options({
        deathState = 'Alive',
    }, spawn, label)

    H.Equal(#first, 4, 'new characters pick when firstSpawn is picker')
    H.Equal(first[1].label, 'page.firstLocation')
    H.Equal(first[1].coords, config.spawn.default)

    spawn.firstSpawn = 'default'
    H.Equal(#Picker.Options({
        deathState = 'Alive',
    }, spawn, label), 1)
end)

H.Test('The picker lists ids and labels only, and flies over the first place', function()
    openAlive()

    H.Natives = {}
    H.PostNui('select', {
        index = 1,
    })
    H.Advance(3000)

    local spawns = H.LastPage('spawns')

    H.Equal(spawns.focus, 'last')
    H.Equal(spawns.options[1], {
        id = 'last',
        label = 'label:page.lastLocation',
        street = 'Vespucci Boulevard',
    })
    H.Equal(spawns.options[2], {
        id = 'legion',
        label = 'label:spawns.legion',
    }, 'no coordinates reach the page')
    H.Equal(H.LastPage('screen'), {
        screen = 'spawn',
    })

    local focus = H.CallsOf('SetFocusPosAndVel')

    H.Equal({ focus[#focus].args[1], focus[#focus].args[2] }, { HOME.x, HOME.y }, 'streaming follows the camera')

    local cameras = H.CallsOf('SetCamCoord')
    local height = cameras[#cameras].args[4]

    H.Assert(math.abs(height - (HOME.z + 38.0)) < 0.01, 'an aerial orbit, got ' .. height)
end)

H.Test('Hovering another place flies there; forged ids are refused', function()
    openAlive()
    H.PostNui('select', {
        index = 1,
    })
    H.Advance(3000)

    H.Equal(H.PostNui('spawnHover', {
        id = 'sandy',
    }), {
        ok = true,
    })
    H.Advance(1500)

    local focus = H.CallsOf('SetFocusPosAndVel')

    H.Equal(focus[#focus].args[1], 1853.86)

    for _, body in ipairs({
        {
            id = 'nowhere',
        },
        {
            id = 5,
        },
        'sandy',
        {},
    }) do
        H.Equal(H.PostNui('spawnHover', body), {
            ok = false,
        })
        H.Equal(H.PostNui('spawnChoose', body), {
            ok = false,
        })
    end
end)

H.Test('Choosing a place asks the server, dives, and gives streaming back', function()
    local character = openAlive()
    local SANDY = vector4(1853.86, 3685.0, 34.27, 210.0)

    H.Respond.Play = function(characterId, spawnId)
        H.Equal({ characterId, spawnId }, { character.id, 'sandy' })

        return {
            ok = true,
            destination = SANDY,
            deathState = 'Alive',
        }
    end
    H.Respond.Arrived = function()
        return {
            ok = true,
        }
    end

    H.PostNui('select', {
        index = 1,
    })
    H.Advance(3000)
    H.PostNui('spawnChoose', {
        id = 'sandy',
    })

    H.Capture(function()
        H.Advance(9000)
    end)

    H.Equal(H.Requests[2].name, 'Play')
    H.Assert(#H.CallsOf('ClearFocus') >= 1, 'streaming follows the player again')

    local placements = H.CallsOf('SetEntityCoordsNoOffset')

    H.Equal(placements[#placements].args[2], SANDY.x)
    H.Equal(H.PageMessages()[#H.PageMessages()].action, 'close')
end)

H.Test('Back from the picker returns to the lineup', function()
    openAlive()
    H.PostNui('select', {
        index = 1,
    })
    H.Advance(3000)

    H.PostNui('cancel', {})
    H.Advance(1500)

    H.Equal(H.LastPage('screen'), {
        screen = 'select',
    })

    local camera = defaults().scene.camera.coords
    local focus = H.CallsOf('SetFocusPosAndVel')

    H.Equal({ focus[#focus].args[1], focus[#focus].args[2] }, { camera.x, camera.y }, 'streaming back on the lineup')
    H.Equal(#H.CallsOf('ClearFocus'), 0, 'not on the hidden player')
    H.Equal(H.PostNui('spawnHover', {
        id = 'sandy',
    }).ok, true, 'still a known id, but ignored outside the picker')
    H.Equal(#H.Requests, 1, 'only List')
end)

H.Test('Frontend sounds follow the owner switch', function()
    open()
    H.Advance(9000)
    H.PostNui('hover', {
        index = 2,
    })
    H.Equal(H.CallsOf('PlaySoundFrontend')[1].args, { -1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true })

    H.Reset()
    H.Respond.List = function()
        local answer = listAnswer({})

        answer.sounds = false

        return answer
    end

    H.Capture(function()
        H.Load('client')
        H.PostNui('ready', {})
        H.Advance(9000)
    end)

    H.PostNui('hover', {
        index = 2,
    })
    H.Equal(#H.CallsOf('PlaySoundFrontend'), 0)
end)

---Loads the client with owner values changed in the List answer.
---@param change fun(answer: table)
local function openWith(change)
    H.Reset()
    H.Respond.List = function()
        local answer = listAnswer({})

        change(answer)

        return answer
    end

    H.Capture(function()
        H.Load('client')
        H.PostNui('ready', {})
    end)
end

H.Test('The page gets the owner look, the theme merged onto ug-lib', function()
    openWith(function(answer)
        answer.theme = {
            colors = {
                violet = '10 80% 50%',
            },
        }
        answer.layout = {
            side = 'right',
            slots = 'top',
        }
        answer.details = { 'location' }
    end)

    local config = H.LastPage('config')

    H.Equal(config.theme.colors.violet, '10 80% 50%')
    H.Equal(config.layout, {
        side = 'right',
        slots = 'top',
    })
    H.Equal(config.details, { 'location' })
    H.Equal(config.skippable, true)
    H.Equal(UgMc.Internal.Nui.Theme(nil, {
        colors = {
            sky = '1 1% 1%',
        },
    }).colors, {
        sky = '1 1% 1%',
    })
end)

H.Test('An unskippable intro ignores skip, and the page knows', function()
    openWith(function(answer)
        answer.cinematic.skippable = false
    end)

    H.Equal(H.LastPage('config').skippable, false)
    H.PostNui('skip', {})
    H.Advance(500)
    H.Equal(H.LastPage('screen'), {
        screen = 'intro',
    })
end)

H.Test('Sounds use the owner names, and a sound left out is silent', function()
    openWith(function(answer)
        answer.soundEffects = {
            select = {
                name = 'GO',
                set = 'MY_SET',
            },
        }
    end)
    H.Advance(9000)

    H.PostNui('hover', {
        index = 2,
    })
    H.Equal(#H.CallsOf('PlaySoundFrontend'), 0)

    H.PostNui('select', {
        index = 2,
    })
    H.Advance(100)
    H.Equal(H.CallsOf('PlaySoundFrontend')[1].args, { -1, 'GO', 'MY_SET', true })
end)

H.Done()
