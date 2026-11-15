--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@type TestHelpers
local H = dofile('tests/helpers.lua')

local MALE, FEMALE = 'mp_m_freemode_01', 'mp_f_freemode_01'
local HOME = vector4(-1037.5, -2737.25, 20.17, 330.0)
local FIELDS = {
    firstName = 'Rui',
    lastName = 'Costa',
    birthDate = '1990-01-01',
    sex = 'male',
}

---@return table
local function defaults()
    return H.Defaults()
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
        cinematic = config.cinematic,
        spawn = {
            points = config.spawn.points,
            firstSpawn = 'default',
            default = config.spawn.default,
        },
        appearance = config.appearance,
        allowDelete = true,
        sounds = false,
    }
end

---ug-appearance as the contract describes it, recording every call.
---@param made? table what OpenCreator answers, nil for a cancel
---@return { calls: table[], appearances: table<integer, table> }
local function provider(made)
    local record = {
        calls = {},
        appearances = {
            [4] = {
                model = FEMALE,
                hair = {
                    style = 7,
                },
            },
        },
    }

    H.NativeReturns.GetResourceState = function(name)
        return name == 'ug-appearance' and 'started' or 'missing'
    end
    H.ResourceExports['ug-appearance'] = {
        Fetch = function(ids)
            record.calls[#record.calls + 1] = {
                name = 'Fetch',
                args = { ids },
            }

            return record.appearances
        end,
        Apply = function(ped, appearance)
            record.calls[#record.calls + 1] = {
                name = 'Apply',
                args = { ped, appearance },
            }

            return true
        end,
        OpenCreator = function(ped, options)
            record.calls[#record.calls + 1] = {
                name = 'OpenCreator',
                args = { ped, options },
            }

            return made
        end,
    }

    return record
end

---@param record table
---@param name string
---@return table[]
local function callsOf(record, name)
    local list = {}

    for _, call in ipairs(record.calls) do
        if call.name == name then
            list[#list + 1] = call
        end
    end

    return list
end

---Opens the scene with one male character in slot 1, ug-appearance running or not.
---@param made? table
---@param withProvider? boolean
---@return table? record
local function open(made, withProvider)
    H.Reset()

    local record = withProvider ~= false and provider(made) or nil

    H.Respond.List = function()
        return listAnswer({
            {
                id = 4,
                name = 'Ana Silva',
                data = {
                    model = MALE,
                },
                deathState = 'Alive',
            },
        })
    end

    H.Capture(function()
        H.Load('client')
        H.PostNui('ready', {})
        H.Advance(9000)
    end)

    return record
end

---Opens creation on slot 2 and submits the form.
---@param record table
local function submit(record)
    H.PostNui('select', {
        index = 2,
    })
    H.Advance(1000)
    H.Natives = {}
    record.calls = {}
    H.Equal(H.PostNui('submit', {
        fields = FIELDS,
        model = MALE,
    }), {
        ok = true,
    })
    H.Advance(2000)
end

print('appearance')

H.Test('without ug-appearance the lineup shows the saved model and nothing is called', function()
    open(nil, false)

    H.Equal(H.CallsOf('CreatePed')[1].args[2], MALE)
end)

H.Test('the lineup uses the appearance model and dresses each character', function()
    local record = assert(open())

    H.Equal(callsOf(record, 'Fetch')[1].args[1], { 4 }, 'own character ids only')
    H.Equal(H.CallsOf('CreatePed')[1].args[2], FEMALE, 'the appearance model wins over data.model')

    local applied = callsOf(record, 'Apply')

    H.Equal(#applied, 1, 'placeholders are not dressed')
    H.Equal(applied[1].args[2].hair.style, 7)
end)

H.Test('submitting opens the creator on the preview ped, then creates with its model', function()
    local made = {
        model = FEMALE,
        hair = {
            style = 3,
        },
    }
    local record = assert(open(made))
    local created = nil

    H.Respond.Create = function(input)
        created = input

        return {
            ok = true,
            characterId = 9,
        }
    end

    submit(record)

    local opened = callsOf(record, 'OpenCreator')

    H.Equal(#opened, 1)
    H.Equal(opened[1].args[2], {
        models = { MALE, FEMALE },
    })
    H.Equal(created, {
        fields = FIELDS,
        model = FEMALE,
    }, 'the model comes from the editor')
    H.Assert(#H.CallsOf('RenderScriptCams') >= 1, 'the scene camera renders again')
    H.Equal(H.LastPage('result'), {
        kind = 'create',
        ok = true,
    })
end)

H.Test('cancelling the creator keeps the form and creates nothing', function()
    local record = assert(open(nil))

    submit(record)

    H.Equal(#callsOf(record, 'OpenCreator'), 1)
    H.Equal(H.LastPage('result'), {
        kind = 'create',
        ok = false,
    }, 'no error: the form only unlocks')
    H.Equal(H.LastPage('screen'), nil, 'the form stays mounted with its values')
    H.Equal(#H.Requests, 1, 'only List')

    local focus = H.CallsOf('SetNuiFocus')

    H.Equal(focus[#focus].args, { true, true })
end)

H.Test('a refused create keeps the look: the next submit does not reopen the editor', function()
    local record = assert(open({
        model = FEMALE,
    }))
    local attempts = 0

    H.Respond.Create = function()
        attempts = attempts + 1

        return {
            ok = false,
            error = 'invalid_args',
        }
    end

    submit(record)
    H.Equal(H.LastPage('result'), {
        kind = 'create',
        ok = false,
        error = 'invalid_args',
    })

    H.PostNui('submit', {
        fields = FIELDS,
        model = MALE,
    })
    H.Advance(2000)

    H.Equal(attempts, 2)
    H.Equal(#callsOf(record, 'OpenCreator'), 1)
end)

H.Test('choosing another body forgets the look', function()
    local record = assert(open({
        model = FEMALE,
    }))

    H.Respond.Create = function()
        return {
            ok = false,
            error = 'invalid_args',
        }
    end

    submit(record)
    H.PostNui('model', {
        model = MALE,
    })
    H.Advance(500)
    H.PostNui('submit', {
        fields = FIELDS,
        model = MALE,
    })
    H.Advance(2000)

    H.Equal(#callsOf(record, 'OpenCreator'), 2)
end)

H.Test('playing dresses the player with the saved look', function()
    local record = assert(open())

    H.Respond.Play = function()
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

    record.calls = {}
    H.PostNui('select', {
        index = 1,
    })

    H.Capture(function()
        H.Advance(9000)
    end)

    H.Equal(H.CallsOf('SetPlayerModel')[1].args[2], FEMALE)

    local applied = callsOf(record, 'Apply')

    H.Equal(applied[1].args[1], 1, 'the player ped')
    H.Equal(applied[1].args[2].hair.style, 7)
end)

H.Test('a failing provider falls back to the model', function()
    H.Reset()
    provider(nil)
    H.ResourceExports['ug-appearance'].Fetch = function()
        error('boom')
    end
    H.Respond.List = function()
        return listAnswer({
            {
                id = 4,
                name = 'Ana Silva',
                data = {
                    model = MALE,
                },
                deathState = 'Alive',
            },
        })
    end

    H.Capture(function()
        H.Load('client')
        H.PostNui('ready', {})
        H.Advance(9000)
    end)

    H.Equal(H.CallsOf('CreatePed')[1].args[2], MALE)
end)

H.Done()
