--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@type TestHelpers
local H = dofile('tests/helpers.lua')

---Starts the server side with an owner config.lua, or none.
---@param owner? string
---@return string[] lines
local function start(owner)
    H.Reset()

    if owner then
        H.Files['config.lua'] = owner
    end

    return H.Load('server')
end

---@param lines string[]
---@return string[] errors without the file prefix
local function errorsOf(lines)
    local errors = {}

    for _, line in ipairs(lines) do
        local message = line:match('%[ERROR%] config%.lua: (.+)$')

        if message then
            errors[#errors + 1] = message
        end
    end

    return errors
end

H.Test('A missing config.lua is generated from the example, and the defaults start', function()
    local lines = start()

    H.Equal(H.Saved['config.lua'], LoadResourceFile('ug-multicharacter', 'server/config.default.lua'))
    H.ExpectLine(lines, 'Generated config.lua.')
    H.ExpectLine(lines, '[ug-multicharacter] v1.0.0 ready: 3 spawn points, 4 slots.')
    H.Equal(UgMc.Internal.Ready, true)
end)

H.Test('Owner values merge over the defaults: tables per key, arrays replace', function()
    start([[
        return {
            scene = { time = { hour = 8 } },
            spawn = { points = { { id = 'airport', label = 'Airport', coords = vector4(-1037.5, -2737.25, 20.17, 330.0) } } },
            cinematic = { title = 'Welcome to Los Santos', timecycle = 'cinema' },
        }
    ]])

    local config = UgMc.Internal.Config.Get()

    H.Equal(config.scene.time, {
        hour = 8,
        minute = 45,
    })
    H.Equal(#config.spawn.points, 1)
    H.Equal(config.spawn.points[1].id, 'airport')
    H.Equal(#config.scene.slots, 4, 'other scene keys keep their defaults')
    H.Equal(config.cinematic.title, 'Welcome to Los Santos')
    H.Equal(config.cinematic.timecycle, 'cinema')
    H.Equal(config.cinematic.intro, true)
end)

H.Test('Every error is reported, then the resource stays idle', function()
    local lines = start([[
        return {
            fields = {
                { name = 'firstName', type = 'text', label = 'First name', max = 24 },
                { name = 'firstName', type = 'text', label = 'Again', max = 24 },
            },
            nameFormat = '{firstName} {surname}',
            spawn = { points = {
                { id = 'last', label = 'Reserved', coords = vector4(0.0, 0.0, 70.0, 0.0) },
            } },
            switchCommand = 'log out',
            cinematic = { timecycle = true },
            scene = { slots = { { coords = vector4(1.0, 2.0, 3.0, 0.0), animation = { dict = 'a', name = 'b', scenario = 'c' } } } },
            isolat = false,
        }
    ]])

    local errors = errorsOf(lines)

    -- nameFormat is not checked while fields are invalid.
    H.Equal(#errors, 6, table.concat(errors, '\n'))
    H.ExpectLine(errors, 'fields: name "firstName" is used twice')
    H.ExpectLine(errors, 'spawn.points[1]: id "last" is reserved')
    H.ExpectLine(errors, 'switchCommand: MUST match the expected format')
    H.ExpectLine(errors, 'cinematic.timecycle: MUST be a string or false')
    H.ExpectLine(errors, 'scene.slots[1].animation: MUST be { dict, name, flag? } or { scenario }')
    H.ExpectLine(errors, 'unknown key "isolat". Did you mean "isolate"?')
    H.ExpectLine(lines, 'Config invalid: 6 error(s). ug-multicharacter stays idle.')
    H.Equal(UgMc.Internal.Ready, false)
end)

H.Test('Cinematic moments merge per key, and false turns off the reopen shots and the select gesture', function()
    local lines = start([[
        return { cinematic = { reopen = false, focus = { fov = 30.0 }, select = { animation = false } } }
    ]])

    H.Equal(errorsOf(lines), {})

    local cinematic = UgMc.Internal.Config.Get().cinematic

    H.Equal(cinematic.reopen, false)
    H.Equal(cinematic.focus.fov, 30.0)
    H.Equal(cinematic.focus.distance, 2.4, 'other focus keys keep their defaults')
    H.Equal(cinematic.select.animation, false)
    H.Equal(cinematic.select.duration, 1600)
end)

H.Test('Cinematic moments are checked with their path', function()
    for path, value in pairs({
        ['cinematic.dive.ease'] = "dive = { ease = 'bounce' }",
        ['cinematic.flyover.fov'] = 'flyover = { fov = 200.0 }',
        ['cinematic.titleDelay'] = 'titleDelay = -1',
        ['cinematic.select.animation'] = "select = { animation = 'wave' }",
    }) do
        local errors = errorsOf(start(('return { cinematic = { %s } }'):format(value)))

        H.Equal(#errors, 1, value)
        H.Equal(errors[1]:find(path, 1, true), 1, errors[1])
    end
end)

H.Test('nameFormat may only use field names', function()
    local errors = errorsOf(start([[ return { nameFormat = '{firstName} {surname}' } ]]))

    H.Equal(errors, { 'nameFormat: "{surname}" is not a field name' })
end)

H.Test('Field rules: select needs options, text needs max, min under max', function()
    local errors = errorsOf(start([[
        return { fields = {
            { name = 'firstName', type = 'text', label = 'First name', min = 2, max = 24 },
            { name = 'lastName', type = 'text', label = 'Last name', min = 2, max = 24 },
            { name = 'sex', type = 'select', label = 'Sex' },
        } }
    ]]))

    H.Equal(#errors, 1)
    H.ExpectLine(errors, 'a select field MUST have options')
end)

H.Test('A syntax error is one error', function()
    local lines = start('return { isolate = }')

    H.Equal(#errorsOf(lines), 1)
    H.ExpectLine(lines, 'Config invalid: 1 error(s).')
end)

H.Test('Idle without ug-core ready, without the characters module, or with too few slots', function()
    H.Reset()
    H.CoreReady = false
    H.ExpectLine(H.Load('server'), 'ug-core did not become ready.')

    H.Reset()
    H.Modules.characters = false
    H.ExpectLine(H.Load('server'), "ug-core's characters module is disabled.")

    H.Reset()
    H.CoreConfig.characters.maxCharacters = 6

    local lines = H.Load('server')

    H.ExpectLine(lines, 'scene has 4 slots, ug-core maxCharacters is 6.')
    H.Equal(UgMc.Internal.Ready, false)
end)

H.Test('Look tables merge onto the defaults, sounds replace', function()
    H.Reset()
    H.Files['config.lua'] = [[
        return {
            layout = { side = 'right' },
            details = { 'born' },
            soundEffects = { back = { name = 'BACK', set = 'HUD_FRONTEND_DEFAULT_SOUNDSET' } },
            cinematic = { skippable = false },
            theme = { colors = { teal = '170 70% 40%' } },
        }
    ]]
    H.Load('server')

    local config = UgMc.Internal.Config.Get()

    H.Equal(config.layout.side, 'right')
    H.Equal(config.layout.slots, 'bottom')
    H.Equal(config.details, { 'born' })
    H.Equal(config.soundEffects, {
        back = {
            name = 'BACK',
            set = 'HUD_FRONTEND_DEFAULT_SOUNDSET',
        },
    })
    H.Equal(config.cinematic.skippable, false)
    H.Equal(config.cinematic.fadeIn, 900)
    H.Equal(config.theme.colors.teal, '170 70% 40%')
end)

H.Test('Bad look values are reported', function()
    H.Reset()
    H.Files['config.lua'] = [[
        return {
            layout = { slots = 'left' },
            details = { 'born', 'born' },
            soundEffects = { open = { name = 'A', set = 'B' } },
            theme = { colors = { violet = 'purple' } },
            cinematic = { skippable = 'yes' },
        }
    ]]

    local lines = H.Load('server')

    for _, key in ipairs({ 'layout', 'details', 'soundEffects', 'theme', 'cinematic' }) do
        H.ExpectLine(lines, key)
    end
end)

H.Done()
