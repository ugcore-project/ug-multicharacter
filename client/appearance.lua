--[[

    ug-multicharacter - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

]] --

-- The appearance contract. ug-appearance fills it when it runs; otherwise characters are a model only.

---@class UgMc.Internal.Appearance
local Appearance = {}
UgMc.Internal.Appearance = Appearance

local PROVIDER = 'ug-appearance'

---@return boolean
function Appearance.Enabled()
    return GetResourceState(PROVIDER) == 'started'
end

---The saved appearances of the player's own characters, by character id. Empty without ug-appearance.
---MUST run in a thread.
---@param characters table[] characters from List
---@return table<integer, table>
function Appearance.Fetch(characters)
    if not Appearance.Enabled() or #characters == 0 then
        return {}
    end

    local ids = {}

    for index, character in ipairs(characters) do
        ids[index] = character.id
    end

    local ok, result = pcall(function()
        return exports[PROVIDER]:Fetch(ids)
    end)

    return ok and type(result) == 'table' and result or {}
end

---The model a character shows: its appearance's, else the one saved at creation.
---@param character table
---@param appearance? table
---@return string?
function Appearance.ModelOf(character, appearance)
    if type(appearance) == 'table' and type(appearance.model) == 'string' then
        return appearance.model
    end

    return character.data and character.data.model or nil
end

---Dresses a ped already of the appearance's model. Without ug-appearance the ped keeps its default look.
---@param ped integer
---@param appearance? table
---@return boolean dressed
function Appearance.Dress(ped, appearance)
    if appearance == nil or not Appearance.Enabled() then
        return false
    end

    local ok, dressed = pcall(function()
        return exports[PROVIDER]:Apply(ped, appearance)
    end)

    return ok and dressed == true
end

---Opens the ug-appearance creator over `ped`. MUST run in a thread.
---Returns the appearance, or nil when the player cancelled or ug-appearance failed.
---@param ped integer
---@param models string[] the models the creation form allows
---@return table?
function Appearance.Create(ped, models)
    local ok, appearance = pcall(function()
        return exports[PROVIDER]:OpenCreator(ped, {
            models = models,
        })
    end)

    if not ok then
        print(('[ug-multicharacter] ug-appearance creator failed: %s'):format(tostring(appearance)))

        return nil
    end

    return type(appearance) == 'table' and appearance or nil
end
