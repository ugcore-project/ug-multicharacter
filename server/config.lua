--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- Owner config: config.lua, copied from server/config.default.lua on the first start and never overwritten.
-- Owner values merge over the defaults: tables merge per key, arrays and other values replace.

---@class UgMc.Internal.Config
local Config = {}
UgMc.Internal.Config = Config

local Schema = UgCore.Schema
local Enums = UgMc.Enums

local RESOURCE = GetCurrentResourceName()
local OWNER_FILE = 'config.lua'
-- To verify live: the scene coordinates and the sound names in server/config.default.lua.
local DEFAULT_FILE = 'server/config.default.lua'
local MAX_COORD = 100000

---@param enum table<string, string>
---@return string[]
local function valuesOf(enum)
    local values = {}

    for _, value in pairs(enum) do
        values[#values + 1] = value
    end

    table.sort(values)

    return values
end

local VEC3 = Schema.Vector3({
    maxComponent = MAX_COORD,
})
local VEC4 = Schema.Vector4({
    maxComponent = MAX_COORD,
})
local NAME = Schema.String({
    min = 1,
    max = 64,
})
local ID_PATTERN = '^[%w_%-]+$'

local HSL = Schema.String({
    min = 5,
    max = 24,
    pattern = '^%d+%.?%d* %d+%.?%d*%% %d+%.?%d*%%$',
})
local GAME_NAME = Schema.String({
    min = 1,
    max = 64,
    pattern = '^[%w_%-]+$',
})
local SOUNDS = valuesOf(Enums.Sound)
local DETAILS = valuesOf(Enums.Detail)

-- ug-lib's theme tokens, then the accent colors.
local THEME_TOKENS = {
    'background', 'foreground', 'card', 'cardForeground', 'popover', 'popoverForeground',
    'primary', 'primaryForeground', 'secondary', 'secondaryForeground', 'muted', 'mutedForeground',
    'accent', 'accentForeground', 'destructive', 'destructiveForeground', 'success', 'successForeground',
    'warning', 'warningForeground', 'border', 'input', 'ring',
    'violet', 'indigo', 'blue', 'sky', 'emerald', 'amber', 'rose', 'fuchsia', 'teal',
}

---@param value string
---@return boolean ok
---@return string? message
local function size(value)
    if value:find('^%d*%.?%d+rem$') or value:find('^%d*%.?%d+px$') then
        return true, nil
    end

    return false, 'MUST be a size in rem or px'
end

local CAMERA = Schema.Object({
    coords = VEC3,
    rotation = VEC3,
    fov = Schema.Number({
        min = 10,
        max = 120,
    }),
})

local ANIMATION = Schema.Object({
    dict = Schema.Optional(NAME),
    name = Schema.Optional(NAME),
    flag = Schema.Optional(Schema.Integer({
        min = 0,
        max = 1048575,
    })),
    scenario = Schema.Optional(NAME),
}, {
    validate = function(value)
        local isAnim = value.dict ~= nil and value.name ~= nil
        local isScenario = value.scenario ~= nil

        return isAnim ~= isScenario, 'MUST be { dict, name, flag? } or { scenario }'
    end,
})

local SHOT = Schema.Object({
    from = CAMERA,
    to = CAMERA,
    duration = Schema.Integer({
        min = 100,
        max = 60000,
    }),
    ease = Schema.Optional(Schema.Enum(valuesOf(Enums.Ease))),
    fadeIn = Schema.Optional(Schema.Boolean()),
    fadeOut = Schema.Optional(Schema.Boolean()),
    letterbox = Schema.Optional(Schema.Boolean()),
})

local EASE = Schema.Enum(valuesOf(Enums.Ease))
local MS = Schema.Integer({
    min = 0,
    max = 60000,
})
local METERS = Schema.Number({
    min = 0,
    max = 500,
})
local FOV = Schema.Number({
    min = 10,
    max = 120,
})

local FIELD = Schema.Object({
    name = Schema.String({
        min = 1,
        max = 32,
        pattern = '^%l[%w]*$',
    }),
    type = Schema.Enum(valuesOf(Enums.FieldType)),
    -- Without a label, clients read fields.<name> from locales/<code>.json.
    label = Schema.Optional(NAME),
    min = Schema.Optional(Schema.Integer({
        min = 0,
        max = 64,
    })),
    max = Schema.Optional(Schema.Integer({
        min = 1,
        max = 64,
    })),
    options = Schema.Optional(Schema.Array(Schema.Object({
        value = Schema.String({
            min = 1,
            max = 32,
        }),
        -- Without a label, clients read options.<field>.<value> from locales/<code>.json.
        label = Schema.Optional(NAME),
    }), {
        min = 1,
        max = 50,
    })),
}, {
    validate = function(field)
        if field.type == Enums.FieldType.Select then
            return field.options ~= nil, 'a select field MUST have options'
        end

        if field.options ~= nil then
            return false, 'only select fields have options'
        end

        if field.type == Enums.FieldType.Text and field.max == nil then
            return false, 'a text field MUST have max'
        end

        return field.min == nil or field.max == nil or field.min <= field.max, 'min MUST NOT be greater than max'
    end,
})

---Turns a Schema detail into a config path: `value.slots[1]: ...` under `scene` becomes `scene.slots[1]: ...`.
---@param key string
---@param detail string?
---@return string
local function pathOf(key, detail)
    local text = (detail or 'is invalid'):gsub('^value', '')

    return key .. (text:sub(1, 1) == ':' and '' or (text:sub(1, 1) == '.' or text:sub(1, 1) == '[') and '' or ': ') .. text
end

---@param list table[]
---@param key string
---@return boolean ok
---@return string? message
local function unique(list, key)
    local seen = {}

    for _, entry in ipairs(list) do
        if seen[entry[key]] then
            return false, ('%s "%s" is used twice'):format(key, tostring(entry[key]))
        end

        seen[entry[key]] = true
    end

    return true
end

---Rules per top-level key. `alternatives` are plain values allowed besides the rule, such as `false` to turn a feature off.
---@type { key: string, rule: UgSchemaRule, alternatives?: any[] }[]
local RULES = {
    {
        key = 'fields',
        rule = Schema.Array(FIELD, {
            min = 1,
            max = 12,
            validate = function(list)
                return unique(list, 'name')
            end,
        }),
    },
    {
        key = 'ageRange',
        rule = Schema.Object({
            min = Schema.Integer({
                min = 0,
                max = 150,
            }),
            max = Schema.Integer({
                min = 0,
                max = 150,
            }),
        }, {
            validate = function(value)
                return value.min <= value.max, 'min MUST NOT be greater than max'
            end,
        }),
    },
    {
        key = 'nameFormat',
        rule = Schema.String({
            min = 1,
            max = 128,
        }),
    },
    {
        key = 'scene',
        rule = Schema.Object({
            camera = CAMERA,
            slots = Schema.Array(Schema.Object({
                coords = VEC4,
                animation = ANIMATION,
            }), {
                min = 1,
                max = 32,
            }),
            placeholder = Schema.Object({
                model = NAME,
                animation = ANIMATION,
            }),
            time = Schema.Object({
                hour = Schema.Integer({
                    min = 0,
                    max = 23,
                }),
                minute = Schema.Integer({
                    min = 0,
                    max = 59,
                }),
            }),
            weather = Schema.String({
                min = 1,
                max = 32,
                pattern = '^[%u_]+$',
            }),
        }),
    },
    {
        key = 'spawn',
        rule = Schema.Object({
            default = VEC4,
            firstSpawn = Schema.Enum(valuesOf(Enums.FirstSpawn)),
            points = Schema.Array(Schema.Object({
                id = Schema.String({
                    min = 1,
                    max = 32,
                    pattern = ID_PATTERN,
                }),
                -- Without a label, clients read spawns.<id> from locales/<code>.json.
                label = Schema.Optional(NAME),
                coords = VEC4,
                camera = Schema.Optional(CAMERA),
            }, {
                validate = function(point)
                    return point.id ~= Enums.SpawnId.Last, ('id "%s" is reserved'):format(Enums.SpawnId.Last)
                end,
            }), {
                max = 50,
                validate = function(list)
                    return unique(list, 'id')
                end,
            }),
        }),
    },
    {
        key = 'isolate',
        rule = Schema.Boolean(),
    },
    {
        key = 'bucketBase',
        rule = Schema.Integer({
            min = 1,
            max = 1000000,
        }),
    },
    {
        key = 'deleteCooldown',
        rule = Schema.Integer({
            min = 0,
            max = 600000,
        }),
    },
    {
        key = 'allowDelete',
        rule = Schema.Boolean(),
    },
    {
        key = 'switchCommand',
        rule = Schema.String({
            min = 1,
            max = 32,
            pattern = ID_PATTERN,
        }),
        alternatives = { false },
    },
    {
        key = 'appearance',
        rule = Schema.Object({
            models = Schema.Array(NAME, {
                min = 1,
                max = 20,
            }),
        }),
    },
    {
        key = 'sounds',
        rule = Schema.Boolean(),
    },
    {
        key = 'soundEffects',
        rule = Schema.Map(Schema.Enum(SOUNDS), Schema.Object({
            name = GAME_NAME,
            set = GAME_NAME,
        }), {
            max = #SOUNDS,
        }),
    },
    {
        key = 'theme',
        rule = Schema.Object({
            mode = Schema.Optional(Schema.Enum({ 'dark', 'light' })),
            colors = Schema.Optional(Schema.Map(Schema.Enum(THEME_TOKENS), HSL, {
                max = #THEME_TOKENS,
            })),
            radius = Schema.Optional(Schema.String({
                min = 3,
                max = 16,
                validate = size,
            })),
            font = Schema.Optional(Schema.Enum({ 'Inter' })),
            scale = Schema.Optional(Schema.Number({
                min = 0.75,
                max = 1.5,
            })),
        }),
    },
    {
        key = 'layout',
        rule = Schema.Object({
            side = Schema.Enum(valuesOf(Enums.Side)),
            slots = Schema.Enum(valuesOf(Enums.Place)),
            hint = Schema.Boolean(),
            initials = Schema.Boolean(),
            keyboard = Schema.Boolean(),
            animations = Schema.Boolean(),
        }),
    },
    {
        key = 'details',
        rule = Schema.Array(Schema.Enum(DETAILS), {
            max = #DETAILS,
            validate = function(list)
                local seen = {}

                for _, detail in ipairs(list) do
                    if seen[detail] then
                        return false, ('detail "%s" is listed twice'):format(detail)
                    end

                    seen[detail] = true
                end

                return true
            end,
        }),
    },
    {
        key = 'cinematic',
        rule = Schema.Object({
            -- Booleans and strings are checked below: they are alternatives to the shot list and the title text.
            intro = Schema.Optional(Schema.Array(SHOT, {
                min = 1,
                max = 12,
            })),
            skippable = Schema.Boolean(),
            reopen = Schema.Optional(Schema.Array(SHOT, {
                min = 1,
                max = 12,
            })),
            title = Schema.Optional(Schema.String({
                min = 1,
                max = 64,
            })),
            titleDelay = MS,
            titleDuration = MS,
            letterbox = Schema.Boolean(),
            timecycle = Schema.Optional(Schema.String({
                min = 1,
                max = 64,
            })),
            fadeOut = Schema.Integer({
                min = 0,
                max = 5000,
            }),
            fadeIn = Schema.Integer({
                min = 0,
                max = 5000,
            }),
            focus = Schema.Object({
                duration = MS,
                distance = METERS,
                height = Schema.Number({
                    min = -5,
                    max = 50,
                }),
                fov = FOV,
                ease = EASE,
            }),
            select = Schema.Object({
                duration = MS,
                distance = METERS,
                fov = FOV,
                ease = EASE,
                -- false is checked below: no animation.
                animation = Schema.Optional(Schema.Object({
                    dict = NAME,
                    name = NAME,
                })),
            }),
            create = Schema.Object({
                duration = MS,
                distance = METERS,
                height = Schema.Number({
                    min = -5,
                    max = 50,
                }),
                fov = FOV,
                ease = EASE,
            }),
            flyover = Schema.Object({
                radius = METERS,
                height = METERS,
                speed = Schema.Number({
                    min = 0,
                    max = 90,
                }),
                fov = FOV,
                fade = Schema.Integer({
                    min = 0,
                    max = 5000,
                }),
            }),
            dive = Schema.Object({
                duration = MS,
                distance = METERS,
                height = METERS,
                fov = FOV,
                ease = EASE,
            }),
            arrival = Schema.Object({
                distance = METERS,
                height = METERS,
                fov = FOV,
                hold = MS,
                handover = MS,
            }),
        }),
    },
}

local CINEMATIC_RULE = RULES[#RULES].rule

---Cinematic options that also take a boolean.
local CINEMATIC_BOOLEANS = {
    intro = true,
    reopen = true,
    timecycle = false,
    title = true,
}

---@param value any
---@return boolean
local function isArray(value)
    return type(value) == 'table' and (next(value) == nil or value[1] ~= nil)
end

---@param base table
---@param owner table
---@return table
local function merge(base, owner)
    for key, value in pairs(owner) do
        if type(value) == 'table' and type(base[key]) == 'table' and not isArray(value) and not isArray(base[key]) then
            merge(base[key], value)
        else
            base[key] = value
        end
    end

    return base
end

---Runs owner code in a sandbox with only what a config needs.
---@param content string
---@param name? string file name in errors, config.lua by default
---@return boolean ok
---@return table? values
---@return string? message
local function run(content, name)
    local env = {
        vector2 = vector2, vector3 = vector3, vector4 = vector4,
        vec2 = vec2, vec3 = vec3, vec4 = vec4,
        tonumber = tonumber, tostring = tostring, type = type, pairs = pairs, ipairs = ipairs,
        math = setmetatable({}, {
            __index = math,
        }),
        string = setmetatable({}, {
            __index = string,
        }),
        table = setmetatable({}, {
            __index = table,
        }),
    }

    local chunk, syntaxError = load(content, '@' .. (name or OWNER_FILE), 't', env)

    if not chunk then
        return false, nil, tostring(syntaxError)
    end

    local ok, result = pcall(chunk)

    if not ok then
        return false, nil, tostring(result)
    end

    if type(result) ~= 'table' then
        return false, nil, 'MUST return a table'
    end

    return true, result, nil
end

---A fresh copy of the defaults, read from server/config.default.lua: the only place they live.
---@return table
function UgMc.Internal.Defaults()
    local ok, values, message = run(LoadResourceFile(RESOURCE, DEFAULT_FILE) or '', DEFAULT_FILE)

    if not ok or not values then
        error(('[ug-multicharacter] %s: %s'):format(DEFAULT_FILE, tostring(message)), 2)
    end

    return values
end

---@param values table merged config
---@param errors string[]
local function checkCinematic(values, errors)
    local cinematic = type(values.cinematic) == 'table' and values.cinematic or nil

    if not cinematic then
        return
    end

    -- Swap boolean alternatives out before the schema check, then put them back.
    local saved = {}

    for key in pairs(CINEMATIC_BOOLEANS) do
        if type(cinematic[key]) == 'boolean' then
            saved[key] = cinematic[key]
            cinematic[key] = nil
        end
    end

    local noSelectAnimation = type(cinematic.select) == 'table' and cinematic.select.animation == false

    if noSelectAnimation then
        cinematic.select.animation = nil
    end

    local ok, checked, detail = Schema.Check(CINEMATIC_RULE, cinematic)

    if noSelectAnimation then
        cinematic.select.animation = false

        if ok then
            checked.select.animation = false
        end
    end

    if not ok then
        errors[#errors + 1] = pathOf('cinematic', detail)

        return
    end

    for key, value in pairs(saved) do
        checked[key] = value
    end

    for key, allowsTrue in pairs(CINEMATIC_BOOLEANS) do
        if checked[key] == true and not allowsTrue then
            errors[#errors + 1] = ('cinematic.%s: MUST be a string or false'):format(key)
        end
    end

    values.cinematic = checked
end

---Checks merged values. Returns clean copies of every valid key.
---@param values table
---@return table clean
---@return string[] errors
function Config.Validate(values)
    local errors = {}
    local clean = {}
    local known = {}

    for _, entry in ipairs(RULES) do
        known[entry.key] = true

        local value = values[entry.key]
        local allowed = false

        for _, alternative in ipairs(entry.alternatives or {}) do
            if value == alternative then
                allowed = true
            end
        end

        if allowed then
            clean[entry.key] = value
        elseif entry.key ~= 'cinematic' then
            local ok, checked, detail = Schema.Check(entry.rule, value)

            if ok then
                clean[entry.key] = checked
            else
                errors[#errors + 1] = pathOf(entry.key, detail)
            end
        end
    end

    checkCinematic(values, errors)
    clean.cinematic = values.cinematic

    local names = {}

    for key in pairs(known) do
        names[#names + 1] = key
    end

    for key in pairs(values) do
        if not known[key] then
            local suggestion = type(key) == 'string' and UgLib.String.Suggest(key, names) or nil

            errors[#errors + 1] = ('unknown key "%s".%s'):format(tostring(key), suggestion and (' Did you mean "%s"?'):format(suggestion) or '')
        end
    end

    -- nameFormat MAY only use field names.
    if clean.fields and clean.nameFormat then
        local fields = {}

        for _, field in ipairs(clean.fields) do
            fields[field.name] = true
        end

        for placeholder in clean.nameFormat:gmatch('{(.-)}') do
            if not fields[placeholder] then
                errors[#errors + 1] = ('nameFormat: "{%s}" is not a field name'):format(placeholder)
            end
        end
    end

    return clean, errors
end

---@type table?
local current = nil

---Reads, merges and checks config.lua. Generates it from the example when missing.
---@return boolean ok
---@return string[] errors
function Config.Load()
    local content = LoadResourceFile(RESOURCE, OWNER_FILE)

    if content == nil then
        local example = LoadResourceFile(RESOURCE, DEFAULT_FILE)

        if example and SaveResourceFile(RESOURCE, OWNER_FILE, example, -1) then
            UgCore.Logger.Info('Generated %s.', OWNER_FILE)
        end

        content = example
    end

    local values = UgMc.Internal.Defaults()

    if content then
        local ok, owner, message = run(content)

        if not ok or not owner then
            current = nil

            return false, { ('%s: %s'):format(OWNER_FILE, tostring(message)) }
        end

        -- A sound left out is silent: the owner's map replaces the default instead of merging.
        if owner.soundEffects ~= nil then
            values.soundEffects = owner.soundEffects
        end

        merge(values, owner)
    end

    local clean, errors = Config.Validate(values)

    for index, message in ipairs(errors) do
        errors[index] = ('%s: %s'):format(OWNER_FILE, message)
    end

    current = #errors == 0 and clean or nil

    return #errors == 0, errors
end

---The loaded config. Raises before a successful Load.
---@return table
function Config.Get()
    if not current then
        error('[ug-multicharacter] Config.Get before a successful Config.Load', 2)
    end

    return current
end
