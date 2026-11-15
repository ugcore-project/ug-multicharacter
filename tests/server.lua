--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

---@type TestHelpers
local H = dofile('tests/helpers.lua')

local LEGION = vector4(195.17, -933.77, 30.69, 144.5)
local SANDY = vector4(1853.86, 3685.0, 34.27, 210.0)
local HOME = vector4(-1037.5, -2737.25, 20.17, 330.0)

---@param owner? string config.lua
---@param setup? fun()
local function start(owner, setup)
    H.Reset()

    if owner then
        H.Files['config.lua'] = owner
    end

    if setup then
        setup()
    end

    H.Load('server')
    H.Assert(UgMc.Internal.Ready, 'the resource did not boot')

    UgMc.Internal.Today = function()
        return {
            year = 2026,
            month = 10,
            day = 10,
        }
    end
end

---@param target integer
---@param fields? table
---@param model? string
---@return table? result
---@return string? errorCode
local function create(target, fields, model)
    return H.Call('Create', target, {
        fields = fields or {
            firstName = 'Ana',
            lastName = 'Silva',
            birthDate = '1995-04-12',
            sex = 'female',
        },
        model = model or 'mp_f_freemode_01',
    })
end

---Adds a character owned by `target` without the callback.
---@param target integer
---@param extra? table
---@return integer id
local function seed(target, extra)
    local id = #H.Characters + 1
    local row = {
        id = id,
        identifier = H.Players[target].identifier,
        name = 'Seeded ' .. id,
        data = {},
    }

    for key, value in pairs(extra or {}) do
        row[key] = value
    end

    H.Characters[id] = row

    return id
end

H.Test('List opens the scene in a private bucket, with the client config', function()
    start(nil, function()
        H.Convars.sv_projectName = 'Los Santos RP'
    end)

    local id = seed(1, {
        position = HOME,
        deathState = 'Downed',
    })
    local result = assert(H.Call('List', 1))

    H.Equal(result.ok, true)
    H.Equal(result.slots, 4)
    H.Equal(result.characters[1].id, id)
    H.Equal(result.characters[1].deathState, 'Downed')
    H.Equal(result.characters[1].position, {
        x = HOME.x,
        y = HOME.y,
        z = HOME.z,
    })
    H.Equal(result.cinematic.title, 'Los Santos RP')
    H.Equal(#result.spawn.points, 3)
    H.Equal(result.spawn.default, LEGION, 'the client flies over it for characters without a position')
    H.Equal(result.fields[1].name, 'firstName')
    H.Equal(H.Buckets[1], 5001)
    H.Equal(UgMc.Internal.State.Get(1).phase, 'selecting')
end)

H.Test('With the sessions module, the private bucket is a ug-core session', function()
    start(nil, function()
        H.Modules.sessions = true
    end)

    H.Call('List', 1)
    H.Equal(H.SessionLog, { 'create 1 ug-multicharacter 1', 'join 1 1' })
    H.Equal(H.Buckets[1], nil)
end)

H.Test('A loaded player cannot open the scene, and isolate = false keeps the default bucket', function()
    start('return { isolate = false }')

    H.Players[1].characterId = 7
    H.Equal(H.Call('List', 1), {
        ok = false,
        error = 'no_permission',
    })

    H.Players[1].characterId = nil
    H.Call('List', 1)
    H.Equal(H.Buckets[1], nil)
end)

H.Test('Create builds the name from nameFormat and stores fields and model', function()
    start()
    H.Call('List', 1)

    local result = assert(create(1, {
        firstName = 'João',
        lastName = "O'Neil-Costa",
        birthDate = '2000-02-29',
        sex = 'male',
    }, 'mp_m_freemode_01'))

    H.Equal(result.ok, true)

    local row = H.Characters[result.characterId]

    H.Equal(row.name, "João O'Neil-Costa")
    H.Equal(row.data, {
        firstName = 'João',
        lastName = "O'Neil-Costa",
        birthDate = '2000-02-29',
        sex = 'male',
        model = 'mp_m_freemode_01',
    })
end)

H.Test('Create rejects forged or invalid input before the handler', function()
    start()
    H.Call('List', 1)

    local valid = {
        firstName = 'Ana',
        lastName = 'Silva',
        birthDate = '1995-04-12',
        sex = 'female',
    }

    ---@param changes table
    ---@return table
    local function with(changes)
        local fields = {}

        for key, value in pairs(valid) do
            fields[key] = value
        end

        for key, value in pairs(changes) do
            fields[key] = value ~= false and value or nil
        end

        return fields
    end

    for label, fields in pairs({
        digits = with({
            firstName = 'Ana2',
        }),
        symbols = with({
            lastName = 'Sil<va>',
        }),
        spaces = with({
            firstName = 'Ana  Maria',
        }),
        padded = with({
            lastName = ' Silva',
        }),
        tooShort = with({
            firstName = 'A',
        }),
        tooLong = with({
            lastName = ('a'):rep(25),
        }),
        badDate = with({
            birthDate = '1995-02-30',
        }),
        notADate = with({
            birthDate = '12/04/1995',
        }),
        underage = with({
            birthDate = '2010-01-01',
        }),
        tooOld = with({
            birthDate = '1900-01-01',
        }),
        badOption = with({
            sex = 'robot',
        }),
        missing = with({
            lastName = false,
        }),
        extra = with({
            nickname = 'Ace',
        }),
    }) do
        H.Equal({ create(1, fields) }, { nil, 'invalid_args' }, label)
    end

    H.Equal({ create(1, valid, 'a_c_chop') }, { nil, 'invalid_args' }, 'model not offered')
    H.Equal({ H.Call('Create', 1, 'not a table') }, { nil, 'invalid_args' })
    H.Equal(#H.Characters, 0)
end)

H.Test('Birth dates count the age to the day', function()
    start()
    H.Call('List', 1)

    H.Equal(create(1, {
        firstName = 'Ana',
        lastName = 'Silva',
        birthDate = '2008-10-10',
        sex = 'female',
    }).ok, true, 'exactly 18 today')
    H.Equal({
        create(1, {
            firstName = 'Ana',
            lastName = 'Silva',
            birthDate = '2008-10-11',
            sex = 'female',
        }),
    }, { nil, 'invalid_args' }, '18 tomorrow')
end)

H.Test('Create and Delete need an open scene, and ug-core limits the count', function()
    start()

    H.Equal(create(1), {
        ok = false,
        error = 'no_permission',
    }, 'scene not open')

    H.Call('List', 1)

    for _ = 1, 4 do
        H.Equal(create(1).ok, true)
    end

    H.Equal(create(1), {
        ok = false,
        error = 'no_permission',
    }, 'maxCharacters reached')
end)

H.Test('Delete checks ownership, the cooldown and allowDelete', function()
    start()

    local mine = seed(1)
    local theirs = seed(2)

    H.Call('List', 1)

    H.Equal(H.Call('Delete', 1, theirs), {
        ok = false,
        error = 'not_found',
    })
    H.Equal(H.Call('Delete', 1, mine), {
        ok = true,
    })
    H.Equal(H.Characters[mine].deleted, true)

    local another = seed(1)

    H.Now = H.Now + 5000
    H.Equal(H.Call('Delete', 1, another), {
        ok = false,
        error = 'rate_limited',
    })

    H.Now = H.Now + 6000
    H.Equal(H.Call('Delete', 1, another), {
        ok = true,
    })

    start('return { allowDelete = false }')
    H.Call('List', 1)
    H.Equal(H.Call('Delete', 1, seed(1)), {
        ok = false,
        error = 'no_permission',
    })
end)

H.Test('Spawn rules: last, points, fallback, first spawn and forced last when downed or dead', function()
    start()

    local Resolve = UgMc.Internal.Spawn.Resolve

    local function character(position, deathState)
        return {
            id = 1,
            name = 'x',
            data = {},
            position = position,
            deathState = deathState or 'Alive',
            createdAt = 0,
        }
    end

    H.Equal({ Resolve(character(HOME), 'last') }, { true, HOME, nil })
    H.Equal({ Resolve(character(nil), 'last') }, { true, LEGION, nil }, 'no saved position')
    H.Equal({ Resolve(character(HOME), 'sandy') }, { true, SANDY, nil })
    H.Equal({ Resolve(character(nil), 'sandy') }, { true, SANDY, nil }, 'new characters pick by default')
    H.Equal({ Resolve(character(HOME), 'nowhere') }, { false, nil, 'invalid_args' })
    H.Equal({ Resolve(character(HOME, 'Downed'), 'sandy') }, { true, HOME, nil }, 'downed goes back')
    H.Equal({ Resolve(character(nil, 'Dead'), 'sandy') }, { true, LEGION, nil }, 'dead without a position')

    start("return { spawn = { firstSpawn = 'default' } }")
    H.Equal({ UgMc.Internal.Spawn.Resolve(character(nil), 'sandy') }, { true, LEGION, nil })
    H.Equal({ UgMc.Internal.Spawn.Resolve(character(HOME), 'sandy') }, { true, SANDY, nil }, 'only new characters')
end)

H.Test('Play then Arrived loads the character in the default bucket', function()
    start()

    local id = seed(1, {
        position = HOME,
    })

    H.Call('List', 1)

    local played = assert(H.Call('Play', 1, id, 'last'))

    H.Equal(played, {
        ok = true,
        destination = HOME,
        deathState = 'Alive',
    })
    H.Equal(UgMc.Internal.State.Get(1).phase, 'placing')
    H.Equal(H.Call('Play', 1, id, 'last'), {
        ok = false,
        error = 'no_permission',
    }, 'one flow at a time')

    H.PedCoords[1] = vector3(HOME.x + 3.0, HOME.y, HOME.z)
    H.Equal(H.Call('Arrived', 1), {
        ok = true,
    })
    H.Equal(H.Players[1].characterId, id)
    H.Equal(H.Buckets[1], 0)
    H.Equal(UgMc.Internal.State.Get(1), nil)
    H.Equal(#H.Flags, 0)
end)

H.Test('Play refuses characters of others and unknown spawn points', function()
    start()

    local theirs = seed(2)
    local mine = seed(1)

    H.Call('List', 1)

    H.Equal(H.Call('Play', 1, theirs, 'last'), {
        ok = false,
        error = 'not_found',
    })
    H.Equal(H.Call('Play', 1, mine, 'nowhere'), {
        ok = false,
        error = 'invalid_args',
    })
    H.Equal({ H.Call('Play', 1, mine, '../etc') }, { nil, 'invalid_args' })
    H.Equal(UgMc.Internal.State.Get(1).phase, 'selecting')
end)

H.Test('An arrival far from the destination retries once, then kicks', function()
    start()

    local id = seed(1, {
        position = HOME,
    })

    H.Call('List', 1)
    H.Call('Play', 1, id, 'last')

    H.PedCoords[1] = vector3(0.0, 0.0, 70.0)

    local first = assert(H.Call('Arrived', 1))

    H.Equal(first, {
        ok = false,
        error = 'invalid_args',
        retry = true,
        destination = HOME,
    })
    H.Equal(H.Flags[1].violation, 'OutOfRange')
    H.Equal(H.Players[1].characterId, nil)

    H.Equal(H.Call('Arrived', 1), {
        ok = false,
        error = 'no_permission',
    })
    H.Equal(H.Kicked, { 1 })
    H.Equal(UgMc.Internal.State.Get(1), nil)
end)

H.Test('A failed load sends the player back to the selection, isolated again', function()
    start()

    local id = seed(1, {
        position = HOME,
    })

    H.Call('List', 1)
    H.Call('Play', 1, id, 'last')
    H.PedCoords[1] = vector3(HOME.x, HOME.y, HOME.z)
    H.FailLoad = true

    H.Equal(H.Call('Arrived', 1), {
        ok = false,
        error = 'internal_error',
    })
    H.Equal(UgMc.Internal.State.Get(1).phase, 'selecting')
    H.Equal(H.Buckets[1], 5001)
end)

H.Test('Arrived without Play, and a busy flow, are refused', function()
    start()

    H.Equal(H.Call('Arrived', 1), {
        ok = false,
        error = 'no_permission',
    })

    H.Call('List', 1)
    UgMc.Internal.State.Get(1).busy = true
    H.Equal(create(1), {
        ok = false,
        error = 'rate_limited',
    })
end)

H.Test('Dropping ends the flow', function()
    start()
    H.Call('List', 1)

    H.TriggerEvent('playerDropped', 1)
    H.Equal(UgMc.Internal.State.Get(1), nil)
end)

H.Test('ugmc status and reopen, console only', function()
    start()

    local id = seed(1, {
        position = HOME,
    })

    H.Call('List', 2)
    H.Players[1].characterId = id

    local lines = H.RunCommand('ugmc', 0, { 'status' })

    H.ExpectLine(lines, 'player 2: selecting')
    H.ExpectLine(lines, '1 player(s) in the scene.')

    lines = H.RunCommand('ugmc', 0, { 'reopen', '1' })

    H.ExpectLine(lines, 'Player 1 is back in the scene.')
    H.Equal(H.Players[1].characterId, nil)
    H.Equal(H.Sent[1], {
        target = 1,
        name = 'ug-multicharacter:Open',
        args = {},
    })

    H.Equal(H.RunCommand('ugmc', 5, { 'status' }), {}, 'players get nothing')
    H.Equal(H.Commands.ugmc.restricted, true)
end)

H.Test('The switch command exists only when configured', function()
    start()
    H.Equal(H.Commands.logout, nil)

    start("return { switchCommand = 'logout' }")
    H.Players[1].characterId = seed(1)
    H.RunCommand('logout', 1)

    H.Equal(H.Players[1].characterId, nil)
    H.Equal(H.Sent[1].name, 'ug-multicharacter:Open')
end)

H.Done()
