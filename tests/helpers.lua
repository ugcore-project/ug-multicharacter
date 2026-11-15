--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Test helpers: a tiny runner, CfxLua mocks, and the real ug-core and ug-lib shared code this resource relies on.
-- ug-core and ug-lib are read from the UG_CORE and UG_LIB paths, siblings of this repository by default.

---@class TestHelpers
local H = {}

H.CorePath = os.getenv('UG_CORE') or '../ug-core'
H.LibPath = os.getenv('UG_LIB') or '../ug-lib'

local passed, failed = 0, 0
local rawType = type
local vectorKinds = setmetatable({}, {
    __mode = 'k',
})

---The CfxLua `type` names vectors.
---@param value any
---@return string
type = function(value)
    return rawType(value) == 'table' and vectorKinds[value] or rawType(value)
end

---@param kind string
---@param components table
---@return table
local function newVector(kind, components)
    vectorKinds[components] = kind

    return components
end

function vector2(x, y) return newVector('vector2', { x = x, y = y }) end

function vector3(x, y, z) return newVector('vector3', { x = x, y = y, z = z }) end

function vector4(x, y, z, w) return newVector('vector4', { x = x, y = y, z = z, w = w }) end

vec2, vec3, vec4 = vector2, vector3, vector4

-- Natives and runtime functions, reset by H.Reset.

---@type table<string, string|false> resource files that replace the ones on disk, `false` for a missing file
H.Files = {}
---@type table<string, { options: table, handler: fun(source: integer, ...: any): any }> registered callbacks
H.Callbacks = {}
---@type table<string, { handler: fun(source: integer, args: string[]), restricted: boolean }> registered commands
H.Commands = {}
---@type table<string, function[]> FiveM event handlers
H.Handlers = {}
---@type { target: integer, name: string, args: any[] }[] server-to-client events
H.Sent = {}
---@type { source: integer, violation: string, detail: string? }[]
H.Flags = {}
---@type integer[]
H.Kicked = {}
---@type table<integer, { identifier: string, characterId: integer? }>
H.Players = {}
---@type table[] rows of ug_characters
H.Characters = {}
---@type table<integer, vector3> server-side ped coords by source
H.PedCoords = {}
---@type string[]
H.SessionLog = {}
H.NextSession = 0
---@type table<integer, integer> routing bucket by source
H.Buckets = {}
---@type table<string, string>
H.Convars = {}
H.Now = 0
H.FailLoad = false
---@type table<string, string> files saved with SaveResourceFile
H.Saved = {}
---@type table<string, table<string, any>> ug-core config values by name
H.CoreConfig = {}
---@type table<string, boolean>
H.Modules = {}
H.CoreReady = true

function GetCurrentResourceName()
    return 'ug-multicharacter'
end

---@param _ string
---@param path string
---@return string?
function LoadResourceFile(_, path)
    if H.Files[path] ~= nil then
        return H.Files[path] or nil
    end

    local handle = io.open(path, 'rb')

    if not handle then
        return nil
    end

    local content = handle:read('a')

    handle:close()

    return content
end

function SaveResourceFile(_, path, content)
    H.Saved[path] = content
    H.Files[path] = content

    return true
end

function GetResourceMetadata(_, key)
    return key == 'version' and '1.0.0' or nil
end

---@type { thread: thread, wakeAt: integer }[] threads waiting in Wait
local sleeping = {}

---@param thread thread
local function resume(thread)
    local ok, result = coroutine.resume(thread)

    if not ok then
        error(debug.traceback(thread, tostring(result)), 0)
    end

    if coroutine.status(thread) == 'suspended' then
        sleeping[#sleeping + 1] = {
            thread = thread,
            wakeAt = H.Now + math.max(result or 0, 1),
        }
    end
end

---Like FiveM: the thread runs at once until its first Wait.
function CreateThread(fn)
    resume(coroutine.create(fn))
end

---Yields until H.Advance reaches the time. Outside a thread it only moves the clock.
---@param ms? integer
function Wait(ms)
    if coroutine.isyieldable() then
        coroutine.yield(ms or 0)
    else
        H.Now = H.Now + (ms or 0)
    end
end

---Runs frames of 16 ms until `ms` passed, waking threads whose time came.
---@param ms integer
function H.Advance(ms)
    local target = H.Now + ms

    repeat
        H.Now = math.min(H.Now + 16, target)

        local ready = {}

        for index = #sleeping, 1, -1 do
            if sleeping[index].wakeAt <= H.Now then
                ready[#ready + 1] = table.remove(sleeping, index)
            end
        end

        for index = #ready, 1, -1 do
            resume(ready[index].thread)
        end
    until H.Now >= target
end

---Calls of mocked natives, in order: `{ name, args }`.
---@type { name: string, args: any[] }[]
H.Natives = {}

---@param name string
---@return { name: string, args: any[] }[]
function H.CallsOf(name)
    local list = {}

    for _, call in ipairs(H.Natives) do
        if call.name == name then
            list[#list + 1] = call
        end
    end

    return list
end

---@param name string
---@param ... any
local function record(name, ...)
    H.Natives[#H.Natives + 1] = {
        name = name,
        args = { ... },
    }
end

-- Any other PascalCase global is a native: recorded, answering H.NativeReturns[name] or nil.
setmetatable(_G, {
    __index = function(_, name)
        if type(name) == 'string' and name:find('^%u') then
            return function(...)
                record(name, ...)

                local value = H.NativeReturns[name]

                if rawType(value) == 'function' then
                    return value(...)
                end

                return value
            end
        end

        return nil
    end,
})

---@type table<string, any> answers of auto-mocked natives
H.NativeReturns = {}
---@type table<string, table<string, function>> exports of other resources, called with a colon like FiveM does
H.ResourceExports = {}

exports = setmetatable({}, {
    __index = function(_, resource)
        local list = H.ResourceExports[resource]

        if not list then
            error(('No such export on resource %s'):format(resource))
        end

        return setmetatable({}, {
            __index = function(_, name)
                local method = list[name]

                if not method then
                    error(('No such export %s in resource %s'):format(name, resource))
                end

                return function(_, ...)
                    return method(...)
                end
            end,
        })
    end,
})
---@type table<integer, boolean> controls that read as just pressed once
H.Pressed = {}
H.Faded = false
H.NextEntity = 100

-- Client natives with behavior.

function IsDisabledControlJustPressed(_, control)
    if H.Pressed[control] then
        H.Pressed[control] = nil

        return true
    end

    return false
end

function DoScreenFadeOut(duration)
    record('DoScreenFadeOut', duration)
    H.Faded = true
end

function DoScreenFadeIn(duration)
    record('DoScreenFadeIn', duration)
    H.Faded = false
end

function IsScreenFadedOut()
    return H.Faded
end

function IsScreenFadingOut()
    return false
end

function CreatePed(...)
    record('CreatePed', ...)
    H.NextEntity = H.NextEntity + 1

    return H.NextEntity
end

function CreateCamWithParams(...)
    record('CreateCamWithParams', ...)

    return 7
end

function PlayerPedId()
    return 1
end

function PlayerId()
    return 0
end

function joaat(name)
    return name
end

function DoesEntityExist()
    return true
end

function HasCollisionLoadedAroundEntity()
    return true
end

function NetworkIsPlayerActive()
    return true
end

---@type table<string, fun(body: any, cb: fun(reply: any))> NUI callbacks the client registered
H.NuiCallbacks = {}

function RegisterNUICallback(name, handler)
    H.NuiCallbacks[name] = handler
end

---Posts to a NUI callback like the page does. Returns the reply.
---@param name string
---@param body any
---@return any
function H.PostNui(name, body)
    local reply = nil

    assert(H.NuiCallbacks[name], 'NUI callback not registered: ' .. name)(body, function(value)
        reply = value
    end)

    return reply
end

---Messages sent to the page, in order.
---@return { action: string, payload: any }[]
function H.PageMessages()
    local list = {}

    for _, call in ipairs(H.CallsOf('SendNUIMessage')) do
        list[#list + 1] = call.args[1]
    end

    return list
end

---The payload of the last page message with this action.
---@param action string
---@return any
function H.LastPage(action)
    local found = nil

    for _, message in ipairs(H.PageMessages()) do
        if message.action == action then
            found = message
        end
    end

    return found and found.payload
end

function GetGameTimer()
    return H.Now
end

function GetConvar(name, default)
    return H.Convars[name] or default
end

function SetPlayerRoutingBucket(target, bucket)
    H.Buckets[math.tointeger(tonumber(target))] = bucket
end

function RegisterCommand(name, handler, restricted)
    H.Commands[name] = {
        handler = handler,
        restricted = restricted,
    }
end

function AddEventHandler(name, handler)
    H.Handlers[name] = H.Handlers[name] or {}
    table.insert(H.Handlers[name], handler)
end

---Loads a Lua file into the global environment.
---@param path string
local function run(path)
    local chunk = assert(loadfile(path, 't'))

    chunk()
end

---Loads ug-core's shared code once, then replaces what a consumer reaches through exports with mocks.
local function loadCore()
    for _, file in ipairs({
        'core/shared/init.lua',
        'core/shared/utils/init.lua',
        'core/shared/utils/table.lua',
        'core/shared/utils/string.lua',
        'core/shared/enums/init.lua',
        'core/shared/enums/lifecycle.lua',
        'core/shared/enums/violations.lua',
        'core/shared/enums/errors.lua',
        'core/shared/logger.lua',
        'core/shared/schema.lua',
        'modules/players/shared/enums.lua',
    }) do
        run(H.CorePath .. '/' .. file)
    end

    local Errors = UgCore.Enums.Errors

    UgCore.Callback = {
        Register = function(name, options, handler)
            H.Callbacks[name] = {
                options = options,
                handler = handler,
            }
        end,
    }
    UgCore.Network = {
        TriggerClient = function(target, name, ...)
            H.Sent[#H.Sent + 1] = {
                target = target,
                name = name,
                args = { ... },
            }
        end,
    }
    UgCore.Guard = {
        IsNear = function(target, coords, maxDistance)
            local ped = H.PedCoords[target]

            return ped ~= nil and math.sqrt((ped.x - coords.x) ^ 2 + (ped.y - coords.y) ^ 2 + (ped.z - coords.z) ^ 2) <= maxDistance
        end,
        Flag = function(target, violation, detail)
            H.Flags[#H.Flags + 1] = {
                source = target,
                violation = violation,
                detail = detail,
            }
        end,
    }
    UgCore.Players = {
        Get = function(target)
            local player = H.Players[target]

            return player and {
                source = target,
                identifier = player.identifier,
                characterId = player.characterId,
            } or nil
        end,
        Kick = function(target)
            H.Kicked[#H.Kicked + 1] = target

            return true
        end,
    }
    UgCore.Sessions = {
        Create = function(options)
            H.NextSession = H.NextSession + 1
            H.SessionLog[#H.SessionLog + 1] = ('create %d %s'):format(H.NextSession, options.name)

            return true, H.NextSession, nil
        end,
        Join = function(target, sessionId)
            H.SessionLog[#H.SessionLog + 1] = ('join %d %d'):format(target, sessionId)

            return true, nil
        end,
        Leave = function(target)
            H.SessionLog[#H.SessionLog + 1] = ('leave %d'):format(target)

            return true, nil
        end,
        Destroy = function(sessionId)
            H.SessionLog[#H.SessionLog + 1] = ('destroy %d'):format(sessionId)

            return true, nil
        end,
    }

    ---@param target integer
    ---@return table[]
    local function owned(target)
        local identifier = H.Players[target] and H.Players[target].identifier
        local list = {}

        for _, row in ipairs(H.Characters) do
            if row.identifier == identifier and not row.deleted then
                list[#list + 1] = row
            end
        end

        return list
    end

    UgCore.Characters = {
        GetAll = function(target)
            if not H.Players[target] then
                return false, nil, Errors.NotFound
            end

            local list = {}

            for index, row in ipairs(owned(target)) do
                list[index] = {
                    id = row.id, name = row.name, data = row.data, position = row.position,
                    deathState = row.deathState or UgCore.Enums.DeathState.Alive, createdAt = 0, lastPlayed = row.lastPlayed,
                }
            end

            return true, list, nil
        end,
        Create = function(target, input)
            if #owned(target) >= H.CoreConfig.characters.maxCharacters then
                return false, nil, Errors.NoPermission
            end

            local id = #H.Characters + 1

            H.Characters[id] = {
                id = id,
                identifier = H.Players[target].identifier,
                name = input.name,
                data = input.data,
            }

            return true, id, nil
        end,
        Delete = function(target, characterId)
            for _, row in ipairs(owned(target)) do
                if row.id == characterId then
                    row.deleted = true

                    return true, nil
                end
            end

            return false, Errors.NotFound
        end,
        Load = function(target, characterId)
            if H.FailLoad then
                return false, Errors.InternalError
            end

            for _, row in ipairs(owned(target)) do
                if row.id == characterId then
                    H.Players[target].characterId = characterId

                    return true, nil
                end
            end

            return false, Errors.NotFound
        end,
        Unload = function(target)
            if not H.Players[target].characterId then
                return false, Errors.NotLoaded
            end

            H.Players[target].characterId = nil

            return true, nil
        end,
    }

    UgCore.Lifecycle = {
        Await = function()
            return H.CoreReady
        end,
    }
    UgCore.Modules = {
        IsEnabled = function(name)
            return H.Modules[name] == true
        end,
    }
    UgCore.Config = {
        Get = function(name, key)
            return (H.CoreConfig[name] or {})[key]
        end,
    }
end

local function loadLib()
    for _, file in ipairs({ 'shared/init.lua', 'shared/utils.lua', 'shared/string.lua', 'shared/table.lua' }) do
        run(H.LibPath .. '/' .. file)
    end
end

---Reads script lists from fxmanifest.lua.
---@return table<string, string[]>
local function readManifest()
    local lists = {
        shared = {},
        server = {},
        client = {},
    }
    local groups = {
        shared_script = 'shared', shared_scripts = 'shared',
        server_script = 'server', server_scripts = 'server',
        client_script = 'client', client_scripts = 'client',
    }
    local env = setmetatable({}, {
        __index = function(_, directive)
            return function(value)
                local group = groups[directive]

                if group then
                    for _, entry in ipairs(rawType(value) == 'table' and value or { value }) do
                        table.insert(lists[group], entry)
                    end
                end
            end
        end,
    })

    assert(loadfile('fxmanifest.lua', 't', env))()

    return lists
end

---Fresh mocks. Tests change them before H.Load. `config.lua` starts missing, whatever is on disk.
function H.Reset()
    H.Files, H.Saved = {
        ['config.lua'] = false,
    }, {}
    H.CoreConfig = {
        characters = {
            maxCharacters = 4,
        },
    }
    H.Modules = {
        characters = true,
    }
    H.CoreReady = true
    H.Callbacks, H.Sent, H.Flags, H.Kicked = {}, {}, {}, {}
    H.Players = {
        [1] = {
            identifier = 'license:1',
        },
        [2] = {
            identifier = 'license:2',
        },
    }
    H.Characters = {}
    H.PedCoords = {}
    H.SessionLog, H.NextSession = {}, 0
    H.Buckets = {}
    H.Commands = {}
    H.Handlers = {}
    H.Convars = {}
    H.Now = 1000
    H.FailLoad = false
    H.Natives, H.NativeReturns, H.Pressed, H.Faded, H.NextEntity = {}, {}, {}, false, 100
    H.Respond, H.Requests, H.ClientEvents, H.LocalLoaded, H.BrokenModels = {}, {}, {}, false, {}
    H.NuiCallbacks = {}
    H.ResourceExports = {}
    GlobalState = {}
    sleeping = {}
    UgCore, UgLib, UgMc = nil, nil, nil
end

---Calls a registered callback like ug-core does: the schema first, then the handler.
---@param name string
---@param target integer
---@param ... any
---@return table? result
---@return string? errorCode when ug-core rejects before the handler
function H.Call(name, target, ...)
    local entry = assert(H.Callbacks[name], 'callback not registered: ' .. name)
    local ok, args = UgCore.Schema.Validate(entry.options.schema, ...)

    if not ok or not args then
        return nil, UgCore.Enums.Errors.InvalidArgs
    end

    return entry.handler(target, table.unpack(args, 1, args.n))
end

---Runs every handler of a FiveM event with `source` set, like the runtime.
---@param name string
---@param target integer
function H.TriggerEvent(name, target, ...)
    for _, handler in ipairs(H.Handlers[name] or {}) do
        source = target
        handler(...)
    end

    source = nil
end

---@param name string
---@param target integer
---@param args? string[]
---@return string[] printed lines
function H.RunCommand(name, target, args)
    local command = assert(H.Commands[name], 'command not registered: ' .. name)

    return H.Capture(function()
        command.handler(target, args or {})
    end)
end

---Server answers seen by the client, by callback name without the resource prefix.
---@type table<string, fun(...): table>
H.Respond = {}
---@type { name: string, args: any[] }[] callbacks the client called
H.Requests = {}
---@type table<string, function> server-to-client events the client registered, by short name
H.ClientEvents = {}
H.LocalLoaded = false
---@type string[] models that fail to load
H.BrokenModels = {}

local function installClient()
    UgCore.Callback = {
        Await = function(name, ...)
            local short = name:match('^ug%-multicharacter:(.+)$') or name

            H.Requests[#H.Requests + 1] = {
                name = short,
                args = { ... },
            }

            local respond = H.Respond[short]

            if not respond then
                return false, nil, UgCore.Enums.Errors.NotFound
            end

            return true, respond(...), nil
        end,
    }
    UgCore.Network = {
        Register = function(name, handler)
            H.ClientEvents[name] = handler
        end,
    }
    UgCore.LocalPlayer = {
        IsLoaded = function()
            return H.LocalLoaded
        end,
    }
    UgLib.Enums = UgLib.Enums or {}
    UgLib.Enums.Asset = {
        Model = 'model',
    }
    UgLib.Streaming = {
        Model = function(model)
            record('Streaming.Model', model)

            for _, broken in ipairs(H.BrokenModels) do
                if broken == model then
                    return false
                end
            end

            return true
        end,
        Release = function(kind, name)
            record('Streaming.Release', kind, name)

            return true
        end,
    }
    UgLib.Locale = {
        Create = function()
            return function(key)
                return 'label:' .. key
            end
        end,
        GetCode = function()
            return 'en'
        end,
    }
    UgLib.Enums.GlobalState = {
        Config = 'ug-lib:Config',
    }
    UgLib.Animation = {
        Play = function(ped, dict, name, options)
            record('Animation.Play', ped, dict, name, options)

            return true
        end,
        Scenario = function(ped, scenario)
            record('Animation.Scenario', ped, scenario)
        end,
    }
end

---Loads ug-core and ug-lib, then this resource's shared and side scripts in manifest order.
---@param side 'server'|'client'
---@return string[] printed lines
function H.Load(side)
    return H.Capture(function()
        loadCore()
        loadLib()

        if side == 'client' then
            installClient()
        end

        local manifest = readManifest()

        for _, group in ipairs({ 'shared', side }) do
            for _, path in ipairs(manifest[group]) do
                if path:sub(1, 1) ~= '@' then
                    run(path)
                end
            end
        end
    end)
end

---Runs `fn` and returns every printed line, without color codes.
---@param fn fun()
---@return string[]
function H.Capture(fn)
    local lines = {}
    local original = print

    print = function(...)
        local parts = {}

        for index = 1, select('#', ...) do
            parts[#parts + 1] = tostring((select(index, ...)))
        end

        lines[#lines + 1] = (table.concat(parts, ' '):gsub('%^%d', ''))
    end

    local ok, err = pcall(fn)

    print = original

    if not ok then
        error(err, 0)
    end

    return lines
end

---@param a any
---@param b any
---@return boolean
local function same(a, b)
    if rawType(a) ~= 'table' or rawType(b) ~= 'table' then
        return a == b
    end

    if vectorKinds[a] ~= vectorKinds[b] then
        return false
    end

    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

---@param value any
---@param depth? integer
---@return string
local function show(value, depth)
    depth = depth or 0

    if rawType(value) ~= 'table' then
        return rawType(value) == 'string' and ('%q'):format(value) or tostring(value)
    end

    if depth > 3 then
        return '{...}'
    end

    local parts = {}

    for key, item in pairs(value) do
        parts[#parts + 1] = ('%s = %s'):format(tostring(key), show(item, depth + 1))
    end

    table.sort(parts)

    return (vectorKinds[value] or '') .. '{ ' .. table.concat(parts, ', ') .. ' }'
end

function H.Equal(actual, expected, message)
    if not same(actual, expected) then
        error(('%s\n  expected: %s\n  actual:   %s'):format(message or 'not equal', show(expected), show(actual)), 2)
    end
end

function H.Assert(condition, message)
    if not condition then
        error(message or 'assertion failed', 2)
    end
end

---@param lines string[]
---@param text string
---@return boolean
function H.Contains(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then
            return true
        end
    end

    return false
end

---@param lines string[]
---@param text string
function H.ExpectLine(lines, text)
    if not H.Contains(lines, text) then
        error(('no line contains "%s":\n  %s'):format(text, table.concat(lines, '\n  ')), 2)
    end
end

---Wrong-type values for tests. LuaLS ignores casts on literals.
---@param value any
---@return any
function H.Any(value)
    return value
end

---@param name string
---@param fn fun()
function H.Test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)

    if ok then
        passed = passed + 1
        print('  ok    ' .. name)
    else
        failed = failed + 1
        print('  FAIL  ' .. name .. '\n        ' .. tostring(err):gsub('\n', '\n        '))
    end
end

function H.Done()
    print(('\n%d passed, %d failed'):format(passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

---The defaults, read from server/config.default.lua like the server reads them.
---@return table
function H.Defaults()
    local content = assert(LoadResourceFile('ug-multicharacter', 'server/config.default.lua'))
    local env = setmetatable({}, {
        __index = _G,
    })

    return assert(load(content, '@server/config.default.lua', 't', env))()
end

return H
