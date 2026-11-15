--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The page bridge. The page is untrusted: every callback body is checked here before the flow sees it.

---@class UgMc.Internal.Nui
local Nui = {}
UgMc.Internal.Nui = Nui

local Action = UgMc.Enums.NuiAction
local Callback = UgMc.Enums.NuiCallback

-- Labels the page shows, from locales/<code>.json under `page`. tests/nui.lua checks the file has exactly these.
Nui.LabelKeys = {
    'play', 'create', 'empty', 'born', 'lastPlayed', 'location', 'never', 'downed', 'dead', 'skip', 'slot', 'hint',
    'createTitle', 'back', 'submit', 'model', 'modelMale', 'modelFemale', 'delete', 'deleteTitle', 'deleteHint', 'cancel',
    'errorRequired', 'errorLength', 'errorSymbols', 'errorSpaces', 'errorDate', 'errorAge', 'errorOption',
    'resultInvalid', 'resultDenied', 'resultWait', 'resultFailed',
    'spawnTitle', 'spawnHint', 'spawnGo', 'lastLocation', 'firstLocation',
}
-- Longest form value Lua passes on, in bytes. The server's schema has the real limits.
local MAX_VALUE = 256
-- Callbacks per second the page MAY send. Hovering fast with the mouse stays well under it.
local EVENTS_PER_SECOND = 30

local ready = false
---@type table[] messages sent before the page was ready
local queue = {}
local budget = {
    second = -1,
    count = 0,
}
---@type table<UgMcNuiCallback, fun(value?: any)>
local handlers = {}
---@type { fields: table<string, boolean>, models: table<string, boolean> } what the form MAY send
local form = {
    fields = {},
    models = {},
}
---@type table<string, boolean> spawn ids the picker shows now
local spawnIds = {}

---Sets which spawn ids the page MAY send, while the picker is open.
---@param ids string[]
function Nui.SetSpawns(ids)
    spawnIds = {}

    for _, id in ipairs(ids) do
        spawnIds[id] = true
    end
end

local translate = nil

---A label in the configured language, for text Lua builds itself.
---@param key string such as `page.lastLocation`
---@return string
function Nui.Label(key)
    translate = translate or UgLib.Locale.Create()

    return translate(key)
end

---An owner label, or the locale entry, or `fallback` when the locale has none.
---@param label string?
---@param key string
---@param fallback string
---@return string
function Nui.LabelOr(label, key, fallback)
    if label then
        return label
    end

    local text = Nui.Label(key)

    -- ug-lib returns the key itself when no locale has it.
    return text ~= key and text or fallback
end

---Copies of the form fields with every label filled in.
---@param fields table[]
---@return table[]
function Nui.LabelFields(fields)
    local labeled = {}

    for index, field in ipairs(fields) do
        local copy = UgLib.Table.DeepCopy(field)

        copy.label = Nui.LabelOr(field.label, 'fields.' .. field.name, field.name)

        for _, option in ipairs(copy.options or {}) do
            option.label = Nui.LabelOr(option.label, ('options.%s.%s'):format(field.name, option.value), option.value)
        end

        labeled[index] = copy
    end

    return labeled
end

---Sets which field names and models the page MAY send, from the List answer.
---@param fields { name: string }[]
---@param models string[]
function Nui.SetForm(fields, models)
    form = {
        fields = {},
        models = {},
    }

    for _, field in ipairs(fields) do
        form.fields[field.name] = true
    end

    for _, model in ipairs(models) do
        form.models[model] = true
    end
end

---Sends a message, or queues it until the page is ready.
---@param action UgMcNuiAction
---@param payload? table
function Nui.Send(action, payload)
    local message = {
        action = action,
        payload = payload,
    }

    if ready then
        SendNUIMessage(message)
    else
        queue[#queue + 1] = message
    end
end

---@type table the owner's look from the List answer
local look = {}

---ug-lib's theme with the owner's ug-multicharacter theme on top. Colors merge token by token.
---@param base table? ug-lib's theme
---@param own table? the ug-multicharacter theme
---@return table
function Nui.Theme(base, own)
    base = type(base) == 'table' and base or {}
    own = type(own) == 'table' and own or {}

    local colors = {}

    -- Not ipairs over both: it stops at a missing ug-lib table and drops the owner colors.
    for index = 1, 2 do
        local source = index == 1 and base.colors or own.colors

        if type(source) == 'table' then
            for token, color in pairs(source) do
                colors[token] = color
            end
        end
    end

    return {
        mode = own.mode or base.mode,
        colors = colors,
        radius = own.radius or base.radius,
        font = own.font or base.font,
        scale = own.scale or base.scale,
    }
end

---The page config: the theme, labels in the configured language, and the owner's layout and details.
---@return table
local function config()
    local libConfig = GlobalState[UgLib.Enums.GlobalState.Config]
    local t = UgLib.Locale.Create()
    local labels = {}

    for _, key in ipairs(Nui.LabelKeys) do
        labels[key] = t('page.' .. key)
    end

    return {
        theme = Nui.Theme(type(libConfig) == 'table' and libConfig.theme or nil, look.theme),
        labels = labels,
        locale = UgLib.Locale.GetCode(),
        layout = look.layout,
        details = look.details,
        skippable = look.skippable,
    }
end

---Takes the owner's look from the List answer, and sends the page config again once the page is ready.
---@param result { theme?: table, layout?: table, details?: string[], cinematic?: table }
function Nui.SetLook(result)
    look = {
        theme = result.theme,
        layout = result.layout,
        details = result.details,
        skippable = not (type(result.cinematic) == 'table' and result.cinematic.skippable == false),
    }

    if ready then
        SendNUIMessage({
            action = Action.Config,
            payload = config(),
        })
    end
end

---Sets who receives a page intent. The flow sets one per callback.
---@param callback UgMcNuiCallback
---@param handler fun(value?: any)
function Nui.On(callback, handler)
    handlers[callback] = handler
end

---@return boolean
local function withinBudget()
    local second = GetGameTimer() // 1000

    if budget.second ~= second then
        budget.second, budget.count = second, 0
    end

    budget.count = budget.count + 1

    return budget.count <= EVENTS_PER_SECOND
end

---A slot index from a body: an integer within the lineup, nil otherwise.
---@param body any
---@return integer?
local function indexOf(body)
    -- A number only: some Lua versions also turn the string '1' into an integer.
    local index = type(body) == 'table' and type(body.index) == 'number' and math.tointeger(body.index) or nil

    if index and index >= 1 and index <= UgMc.Internal.Scene.Count() then
        return index
    end

    return nil
end

---A model the owner offers, nil otherwise.
---@param body any
---@return string?
local function modelOf(body)
    local model = type(body) == 'table' and body.model or nil

    return type(model) == 'string' and form.models[model] and model or nil
end

---A clean copy of a submitted form: known field names with bounded strings, and an offered model.
---@param body any
---@return { fields: table<string, string>, model: string }?
local function submissionOf(body)
    local model = modelOf(body)
    local fields = type(body) == 'table' and body.fields or nil

    if not model or type(fields) ~= 'table' then
        return nil
    end

    local clean = {}

    for name, value in pairs(fields) do
        if not form.fields[name] or type(value) ~= 'string' or #value > MAX_VALUE then
            return nil
        end

        clean[name] = value
    end

    return {
        fields = clean,
        model = model,
    }
end

---A spawn id the picker shows now, nil otherwise.
---@param body any
---@return string?
local function spawnIdOf(body)
    local id = type(body) == 'table' and body.id or nil

    return type(id) == 'string' and spawnIds[id] and id or nil
end

---Runs the handler with a checked value, and answers the page.
---@param name UgMcNuiCallback
---@param read fun(body: any): any
local function register(name, read)
    RegisterNUICallback(name, function(body, cb)
        local value = withinBudget() and read(body) or nil

        if value ~= nil and handlers[name] then
            handlers[name](value)
        end

        cb({
            ok = value ~= nil,
        })
    end)
end

RegisterNUICallback(Callback.Ready, function(_, cb)
    ready = true
    SendNUIMessage({
        action = Action.Config,
        payload = config(),
    })

    for _, message in ipairs(queue) do
        SendNUIMessage(message)
    end

    queue = {}
    cb({
        ok = true,
    })
end)

---@return boolean
local function always()
    return true
end

register(Callback.Hover, indexOf)
register(Callback.Select, indexOf)
register(Callback.Delete, indexOf)
register(Callback.Model, modelOf)
register(Callback.Submit, submissionOf)
register(Callback.SpawnHover, spawnIdOf)
register(Callback.SpawnChoose, spawnIdOf)
register(Callback.Skip, always)
register(Callback.Cancel, always)
