--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- List, Create and Delete. Every answer is a table: { ok = true, ... } or { ok = false, error = <UgErrorCode> }.

---@class UgMc.Internal.Characters
local Characters = {}
UgMc.Internal.Characters = Characters

local Config = UgMc.Internal.Config
local State = UgMc.Internal.State
local Schema = UgCore.Schema
local Errors = UgCore.Enums.Errors
local Enums = UgMc.Enums
local Logger = UgCore.Logger

-- Name parts MUST NOT hold digits or symbols. Letters of every language, spaces, apostrophes and hyphens pass.
local NAME_SYMBOLS = '[%d<>{}%[%]\\/@#%$%%%^&%*=%+|~`"!%?;:,%._%(%)]'
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

---Today's date. A function, so tests MAY replace it.
---@return { year: integer, month: integer, day: integer }
function UgMc.Internal.Today()
    local now = os.date('*t')

    return {
        year = now.year,
        month = now.month,
        day = now.day,
    }
end

---@param year integer
---@return boolean
local function isLeap(year)
    return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

---Checks a `YYYY-MM-DD` date: a real calendar day, giving an age inside `ageRange`.
---@param text string
---@return boolean ok
---@return string? message
local function checkBirthDate(text)
    local year, month, day = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')

    year, month, day = tonumber(year), tonumber(month), tonumber(day)

    if not year or month < 1 or month > 12 then
        return false, 'MUST be a date as YYYY-MM-DD'
    end

    local days = DAYS_IN_MONTH[month] + ((month == 2 and isLeap(year)) and 1 or 0)

    if day < 1 or day > days then
        return false, 'MUST be a real date'
    end

    local today = UgMc.Internal.Today()
    local age = today.year - year - ((today.month < month or (today.month == month and today.day < day)) and 1 or 0)
    local range = Config.Get().ageRange

    if age < range.min or age > range.max then
        return false, ('MUST give an age from %d to %d'):format(range.min, range.max)
    end

    return true
end

---@param text string
---@return boolean ok
---@return string? message
local function checkNamePart(text)
    if text ~= text:match('^%s*(.-)%s*$') or text:find('%s%s') then
        return false, 'MUST NOT have extra spaces'
    end

    if text:find(NAME_SYMBOLS) then
        return false, 'MUST NOT have digits or symbols'
    end

    return true
end

---Builds the Create schema from the configured fields.
---@return UgSchema
local function createSchema()
    local config = Config.Get()
    local rules = {}

    for _, field in ipairs(config.fields) do
        if field.type == Enums.FieldType.Text then
            rules[field.name] = Schema.String({
                min = field.min or 1,
                max = field.max,
                validate = checkNamePart,
            })
        elseif field.type == Enums.FieldType.Date then
            rules[field.name] = Schema.String({
                min = 10,
                max = 10,
                validate = checkBirthDate,
            })
        else
            local values = {}

            for index, option in ipairs(field.options) do
                values[index] = option.value
            end

            rules[field.name] = Schema.Enum(values)
        end
    end

    return Schema.Define({
        Schema.Object({
            fields = Schema.Object(rules),
            model = Schema.Enum(config.appearance.models),
        }),
    })
end

---The character name from `nameFormat`.
---@param fields table<string, string>
---@return string
local function nameOf(fields)
    local name = Config.Get().nameFormat:gsub('{(.-)}', function(key)
        return fields[key] or ''
    end)

    return (name:gsub('%s+', ' '):match('^%s*(.-)%s*$'))
end

---What the client may know about one of its characters.
---@param character UgCharacter
---@return table
local function shown(character)
    local position = character.position

    return {
        id = character.id,
        name = character.name,
        data = character.data,
        deathState = character.deathState,
        createdAt = character.createdAt,
        lastPlayed = character.lastPlayed,
        position = position and {
            x = position.x,
            y = position.y,
            z = position.z,
        } or nil,
    }
end

---@return string|false
local function titleOf()
    local title = Config.Get().cinematic.title

    if title == true then
        local name = GetConvar('sv_projectName', '')

        return name ~= '' and name or GetConvar('sv_hostname', 'FiveM')
    end

    return title
end

---Opens the scene: the player's characters and every client value of the config.
---@param source integer
---@return table
function Characters.List(source)
    local player = UgCore.Players.Get(source)

    if not player then
        return {
            ok = false,
            error = Errors.NotFound,
        }
    end

    if player.characterId then
        return {
            ok = false,
            error = Errors.NoPermission,
        }
    end

    local ok, characters, errorCode = UgCore.Characters.GetAll(source)

    if not ok or not characters then
        return {
            ok = false,
            error = errorCode or Errors.InternalError,
        }
    end

    State.Open(source)

    local config = Config.Get()
    local list = {}

    for index, character in ipairs(characters) do
        list[index] = shown(character)
    end

    local points = {}

    for index, point in ipairs(config.spawn.points) do
        points[index] = {
            id = point.id,
            label = point.label,
            coords = point.coords,
            camera = point.camera,
        }
    end

    local cinematic = UgLib.Table.DeepCopy(config.cinematic)

    cinematic.title = titleOf()

    return {
        ok = true,
        characters = list,
        slots = UgCore.Config.Get('characters', 'maxCharacters'),
        fields = config.fields,
        ageRange = config.ageRange,
        scene = config.scene,
        cinematic = cinematic,
        spawn = {
            points = points,
            firstSpawn = config.spawn.firstSpawn,
            default = config.spawn.default,
        },
        appearance = config.appearance,
        allowDelete = config.allowDelete,
        sounds = config.sounds,
        soundEffects = config.soundEffects,
        theme = config.theme,
        layout = config.layout,
        details = config.details,
    }
end

---@param source integer
---@param input { fields: table<string, string>, model: string }
---@return table
function Characters.Create(source, input)
    local flow = State.Get(source)

    if not flow or flow.phase ~= Enums.Phase.Selecting then
        return {
            ok = false,
            error = Errors.NoPermission,
        }
    end

    return State.Exclusive(flow, function()
        local data = UgLib.Table.DeepCopy(input.fields)

        data.model = input.model

        local ok, characterId, errorCode = UgCore.Characters.Create(source, {
            name = nameOf(input.fields),
            data = data,
        })

        if not ok then
            return {
                ok = false,
                error = errorCode or Errors.InternalError,
            }
        end

        Logger.Debug('player %d created character %d.', source, characterId)

        return {
            ok = true,
            characterId = characterId,
        }
    end)
end

---@param source integer
---@param characterId integer
---@return table
function Characters.Delete(source, characterId)
    local config = Config.Get()
    local flow = State.Get(source)

    if not config.allowDelete or not flow or flow.phase ~= Enums.Phase.Selecting then
        return {
            ok = false,
            error = Errors.NoPermission,
        }
    end

    if flow.lastDelete > 0 and GetGameTimer() - flow.lastDelete < config.deleteCooldown then
        return {
            ok = false,
            error = Errors.RateLimited,
        }
    end

    return State.Exclusive(flow, function()
        local ok, errorCode = UgCore.Characters.Delete(source, characterId)

        if not ok then
            return {
                ok = false,
                error = errorCode or Errors.InternalError,
            }
        end

        flow.lastDelete = GetGameTimer()
        Logger.Debug('player %d deleted character %d.', source, characterId)

        return {
            ok = true,
        }
    end)
end

---Registers the callbacks. Runs once after a clean boot.
function Characters.Register()
    local Callback = UgCore.Callback

    Callback.Register('List', {
        schema = Schema.Define({}),
        rate = {
            max = 5,
            per = 10000,
        },
    }, Characters.List)

    Callback.Register('Create', {
        schema = createSchema(),
        rate = {
            max = 3,
            per = 10000,
        },
    }, Characters.Create)

    Callback.Register('Delete', {
        schema = Schema.Define({
            Schema.Integer({
                min = 1,
                max = 2147483647,
            }),
        }),
        rate = {
            max = 2,
            per = 10000,
        },
    }, Characters.Delete)
end
